import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env', obfuscate: true)
abstract class Env {
  @EnviedField(varName: 'WEBSOCKET_URL', obfuscate: true)
  static final String webSocketUrl = _Env.webSocketUrl;
}
