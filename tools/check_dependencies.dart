// Dependency-only network request: never sends source code or vault contents.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final text = File('app/pubspec.lock').readAsStringSync();
    final blocks = RegExp(
      r'^  ([a-zA-Z0-9_]+):\r?\n([\s\S]*?)(?=^  [a-zA-Z0-9_]+:|^sdks:)',
      multiLine: true,
    ).allMatches(text);
    final queries = <Map<String, Object>>[];
    var sdkPackages = 0;
    for (final block in blocks) {
      final body = block[2]!;
      final source = RegExp(
        r'^    source: (\w+)',
        multiLine: true,
      ).firstMatch(body)?[1];
      if (source == 'sdk') {
        sdkPackages++;
        continue;
      }
      if (source != 'hosted')
        throw StateError('Unsupported source for ${block[1]}');
      final version = RegExp(
        r'^    version: "([^"]+)"',
        multiLine: true,
      ).firstMatch(body)?[1];
      if (version == null) throw StateError('Missing version for ${block[1]}');
      queries.add({
        'package': {'name': block[1]!, 'ecosystem': 'Pub'},
        'version': version,
      });
    }
    if (queries.isEmpty) throw StateError('No hosted dependencies found');
    final request = await client.postUrl(
      Uri.parse('https://api.osv.dev/v1/querybatch'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'queries': queries}));
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200)
      throw HttpException('OSV HTTP ${response.statusCode}');
    final results =
        (jsonDecode(body) as Map<String, dynamic>)['results'] as List;
    if (results.length != queries.length)
      throw StateError('Incomplete OSV response');
    Directory('dist/ci').createSync(recursive: true);
    File(
      'dist/ci/osv.json',
    ).writeAsStringSync(jsonEncode({'queries': queries, 'results': results}));
    var findings = 0;
    for (var i = 0; i < results.length; i++) {
      final result = results[i] as Map<String, dynamic>;
      if (result.containsKey('next_page_token'))
        throw StateError('Paginated OSV result: manual investigation required');
      final vulns = result['vulns'] as List? ?? [];
      for (final vuln in vulns) {
        stdout.writeln('${queries[i]}: ${vuln['id']}');
        findings++;
      }
    }
    stdout.writeln(
      'OSV: ${queries.length} hosted packages, $findings findings; $sdkPackages SDK packages outside scope.',
    );
    if (findings > 0) exitCode = 1;
  } catch (error) {
    stderr.writeln('Dependency audit failed: $error');
    exitCode = 2;
  } finally {
    client.close(force: true);
  }
}
