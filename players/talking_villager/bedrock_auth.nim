## AWS auth for Bedrock InvokeModel without a bearer token, ported from
## Crewrift's notsus bot. Resolves credentials through the hosted chain
## (static env keys, container endpoint, IRSA web identity), signs requests
## with SigV4, and detects the runner Bedrock sidecar endpoint.

import
  std/[algorithm, json, os, strutils, times, uri],
  crunchy/sha256,
  curly

const
  SidecarEndpointEnv = "AWS_ENDPOINT_URL_BEDROCK_RUNTIME"
  BedrockService = "bedrock"
  AwsRequestType = "aws4_request"
  StsVersion = "2011-06-15"
  StsAction = "AssumeRoleWithWebIdentity"
  MaxMetadataValueLen = 256

type
  BedrockAuthError* = object of CatchableError

  AwsCredentials = object
    accessKeyId: string
    secretAccessKey: string
    sessionToken: string
    source: string

var cachedCredentials: AwsCredentials

let credentialCurl = newCurlPool(1)

proc fail(message: string) {.raises: [BedrockAuthError].} =
  ## Raises one Bedrock auth error.
  raise newException(BedrockAuthError, message)

proc truthy(value: string): bool =
  ## Returns true when an environment flag is enabled.
  case value.strip().toLowerAscii()
  of "1", "true", "yes", "y", "on":
    true
  else:
    false

proc byteHex(value: uint8): string =
  ## Returns one lowercase two-digit hex byte.
  value.toHex(2).toLowerAscii()

proc hex(bytes: openArray[uint8]): string =
  ## Returns a lowercase hex string for bytes.
  for b in bytes:
    result.add b.byteHex()

proc sha256Hex(data: string): string =
  ## Returns the SHA-256 digest as lowercase hex.
  data.sha256().hex()

proc metadataSafe(value: string): string =
  ## Coerces one Bedrock metadata value to the safe character set.
  for ch in value:
    if result.len >= MaxMetadataValueLen:
      break
    if ch in {'A' .. 'Z', 'a' .. 'z', '0' .. '9',
        ' ', ':', '_', '@', '$', '#', '=', '/', '+', ',', '.', '-'}:
      result.add ch
    else:
      result.add '_'

proc metadataKeySafe(value: string): string =
  ## Coerces one Bedrock metadata key to a stable safe form.
  result = value.metadataSafe()
  if result.len == 0:
    result = "tag"

proc awsUriEncode*(value: string): string =
  ## Percent-encodes one AWS URI path label.
  for ch in value:
    if ch in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '.', '_', '~'}:
      result.add ch
    else:
      result.add '%'
      result.add ch.uint8.toHex(2)

proc sidecarEndpoint*(): string =
  ## Returns the runner Bedrock sidecar endpoint if configured.
  getEnv(SidecarEndpointEnv).strip()

proc hasSidecarEndpoint*(): bool =
  ## Returns true when the hosted Bedrock sidecar is configured.
  sidecarEndpoint().len > 0

proc joinUrl*(base, path: string): string =
  ## Joins one base URL and absolute path.
  result = base.strip()
  while result.endsWith("/"):
    result.setLen(result.len - 1)
  if path.len > 0 and not path.startsWith("/"):
    result.add '/'
  result.add path

proc nodeText(node: JsonNode): string =
  ## Converts one JSON node to a metadata-safe string.
  if node.kind == JString:
    return node.getStr()
  $node

proc bedrockRequestMetadata*(playerName: string): JsonNode =
  ## Builds the Bedrock request metadata for cost attribution.
  result = newJObject()
  let raw = getEnv("BEDROCK_REQUEST_METADATA").strip()
  if raw.len > 0:
    let parsed = parseJson(raw)
    if parsed.kind != JObject:
      fail("BEDROCK_REQUEST_METADATA must be a JSON object.")
    for key, value in parsed:
      result[key.metadataKeySafe()] = %value.nodeText().metadataSafe()
  var name = getEnv("COWORLD_POLICY_NAME").strip()
  if name.len == 0:
    name = playerName
  let safeName = name.metadataSafe()
  result["player_name"] = %safeName
  result["bot"] = %safeName
  result["policy_name"] = %safeName

proc xmlTag(body, name: string): string =
  ## Extracts one simple XML tag value.
  let
    openTag = "<" & name & ">"
    closeTag = "</" & name & ">"
    start = body.find(openTag)
  if start < 0:
    return ""
  let valueStart = start + openTag.len
  let stop = body.find(closeTag, valueStart)
  if stop < valueStart:
    return ""
  body[valueStart ..< stop]

proc credentialsFromEnv(): AwsCredentials =
  ## Returns static AWS credentials from the process environment.
  result.accessKeyId = getEnv("AWS_ACCESS_KEY_ID").strip()
  result.secretAccessKey = getEnv("AWS_SECRET_ACCESS_KEY").strip()
  result.sessionToken = getEnv("AWS_SESSION_TOKEN").strip()
  if result.accessKeyId.len > 0 and result.secretAccessKey.len > 0:
    result.source = "env"

proc containerAuthorization(): string =
  ## Returns the container credential authorization token if configured.
  result = getEnv("AWS_CONTAINER_AUTHORIZATION_TOKEN").strip()
  if result.len > 0:
    return
  let path = getEnv("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE").strip()
  if path.len > 0 and fileExists(path):
    result = readFile(path).strip()

proc credentialsFromContainer(): AwsCredentials =
  ## Returns AWS credentials from the container credential endpoint.
  var url = getEnv("AWS_CONTAINER_CREDENTIALS_FULL_URI").strip()
  if url.len == 0:
    let relative = getEnv("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI").strip()
    if relative.len > 0:
      url = "http://169.254.170.2" & relative
  if url.len == 0:
    return
  var headers: seq[(string, string)]
  let token = containerAuthorization()
  if token.len > 0:
    headers.add ("Authorization", token)
  let response = credentialCurl.get(url, headers, timeout = 2.0'f32)
  if response.code != 200:
    fail("Container credentials returned HTTP " & $response.code & ".")
  let data = parseJson(response.body)
  result.accessKeyId = data{"AccessKeyId"}.getStr().strip()
  result.secretAccessKey = data{"SecretAccessKey"}.getStr().strip()
  result.sessionToken = data{"Token"}.getStr().strip()
  if result.accessKeyId.len > 0 and result.secretAccessKey.len > 0:
    result.source = "container"

proc stsBody(roleArn, sessionName, token: string): string =
  ## Builds one STS AssumeRoleWithWebIdentity form body.
  let pairs = [
    ("Action", StsAction),
    ("Version", StsVersion),
    ("RoleArn", roleArn),
    ("RoleSessionName", sessionName),
    ("WebIdentityToken", token),
    ("DurationSeconds", "3600")
  ]
  for pair in pairs:
    if result.len > 0:
      result.add '&'
    result.add encodeUrl(pair[0])
    result.add '='
    result.add encodeUrl(pair[1])

proc credentialsFromWebIdentity(region: string): AwsCredentials =
  ## Returns AWS credentials from IRSA web identity.
  let
    roleArn = getEnv("AWS_ROLE_ARN").strip()
    tokenPath = getEnv("AWS_WEB_IDENTITY_TOKEN_FILE").strip()
  if roleArn.len == 0 or tokenPath.len == 0:
    return
  if not fileExists(tokenPath):
    fail("AWS_WEB_IDENTITY_TOKEN_FILE does not exist.")
  let sessionName =
    if getEnv("AWS_ROLE_SESSION_NAME").strip().len > 0:
      getEnv("AWS_ROLE_SESSION_NAME").strip()
    else:
      "heartleaf-bedrock"
  let body = stsBody(roleArn, sessionName, readFile(tokenPath).strip())
  let endpoint = "https://sts." & region & ".amazonaws.com/"
  let response = credentialCurl.post(
    endpoint,
    @[("Content-Type", "application/x-www-form-urlencoded")],
    body,
    timeout = 4.0'f32
  )
  if response.code != 200:
    fail("STS web identity returned HTTP " & $response.code & ".")
  result.accessKeyId = response.body.xmlTag("AccessKeyId").strip()
  result.secretAccessKey = response.body.xmlTag("SecretAccessKey").strip()
  result.sessionToken = response.body.xmlTag("SessionToken").strip()
  if result.accessKeyId.len > 0 and result.secretAccessKey.len > 0:
    result.source = "web-identity"

proc resolveCredentials(region: string): AwsCredentials =
  ## Resolves AWS credentials through the hosted Bedrock credential chain.
  if cachedCredentials.accessKeyId.len > 0:
    return cachedCredentials
  result = credentialsFromEnv()
  if result.source.len == 0:
    result = credentialsFromContainer()
  if result.source.len == 0:
    result = credentialsFromWebIdentity(region)
  if result.source.len == 0:
    fail("No AWS credentials found for Bedrock.")
  cachedCredentials = result

proc credentialSignalText*(): string =
  ## Returns the first configured AWS credential source name.
  if hasSidecarEndpoint():
    return "sidecar-endpoint"
  if getEnv("AWS_ACCESS_KEY_ID").strip().len > 0 and
      getEnv("AWS_SECRET_ACCESS_KEY").strip().len > 0:
    return "env"
  if getEnv("AWS_CONTAINER_CREDENTIALS_FULL_URI").strip().len > 0 or
      getEnv("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI").strip().len > 0:
    return "container"
  if getEnv("AWS_ROLE_ARN").strip().len > 0 and
      getEnv("AWS_WEB_IDENTITY_TOKEN_FILE").strip().len > 0:
    return "web-identity"
  if getEnv("USE_BEDROCK").truthy():
    return "use-bedrock"

proc hasAwsCredentialSignal*(): bool =
  ## Returns true if Bedrock is enabled or AWS credentials look available.
  credentialSignalText().len > 0

proc canonicalUriPath(path: string): string =
  ## Returns the SigV4 canonical URI: each already-encoded request path
  ## segment URI-encoded once more (double encoding, non-S3 services).
  var first = true
  for segment in path.split('/'):
    if not first:
      result.add '/'
    first = false
    result.add segment.awsUriEncode()

proc canonicalHeaders(
  headers: openArray[(string, string)]
): tuple[text: string, signed: string] =
  ## Builds canonical headers and the signed header list.
  var sorted = @headers
  sorted.sort(
    proc(a, b: (string, string)): int =
      cmp(a[0], b[0])
  )
  for header in sorted:
    result.text.add header[0]
    result.text.add ':'
    result.text.add header[1].strip()
    result.text.add '\n'
    if result.signed.len > 0:
      result.signed.add ';'
    result.signed.add header[0]

proc signingKey(secretKey, dateStamp, regionName: string): array[32, uint8] =
  ## Returns the AWS SigV4 signing key.
  let dateKey = hmacSha256("AWS4" & secretKey, dateStamp)
  let regionKey = hmacSha256(dateKey, regionName)
  let serviceKey = hmacSha256(regionKey, BedrockService)
  hmacSha256(serviceKey, AwsRequestType)

proc signedBedrockHeaders*(
  body, host, path, region: string
): seq[(string, string)] =
  ## Builds AWS SigV4 headers for one Bedrock InvokeModel request.
  let
    credentials = resolveCredentials(region)
    nowUtc = now().utc
    dateStamp = nowUtc.format("yyyyMMdd")
    amzDate = nowUtc.format("yyyyMMdd'T'HHmmss'Z'")
    bodyHash = body.sha256Hex()
  var headers = @[
    ("accept", "application/json"),
    ("content-type", "application/json"),
    ("host", host),
    ("x-amz-content-sha256", bodyHash),
    ("x-amz-date", amzDate)
  ]
  if credentials.sessionToken.len > 0:
    headers.add ("x-amz-security-token", credentials.sessionToken)
  let canonical = canonicalHeaders(headers)
  let scope = dateStamp & "/" & region & "/" & BedrockService & "/" &
    AwsRequestType
  let canonicalRequest = "POST\n" & path.canonicalUriPath() & "\n\n" &
    canonical.text & "\n" & canonical.signed & "\n" & bodyHash
  let stringToSign = "AWS4-HMAC-SHA256\n" & amzDate & "\n" & scope &
    "\n" & canonicalRequest.sha256Hex()
  let signature = hmacSha256(
    signingKey(credentials.secretAccessKey, dateStamp, region),
    stringToSign
  ).hex()
  let authorization = "AWS4-HMAC-SHA256 Credential=" &
    credentials.accessKeyId & "/" & scope &
    ", SignedHeaders=" & canonical.signed &
    ", Signature=" & signature
  headers.add ("authorization", authorization)
  result = headers
