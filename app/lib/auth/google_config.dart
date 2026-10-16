/// Client ID of the *Web* OAuth client in the project's Google Cloud project
/// (see docs/setup-google-cloud.md). Not a secret: Android needs it to ask
/// for sign-in, and no server ever receives a token for it.
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
