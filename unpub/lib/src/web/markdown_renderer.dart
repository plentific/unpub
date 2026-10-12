import 'package:markdown/markdown.dart' as markdown;
import 'package:sanitize_html/sanitize_html.dart';

/// Turns the Markdown of a readme or changelog into HTML that is safe to put
/// in a page. Markdown passes raw HTML through, and packages come from many
/// uploaders, so scripts, event handlers and `javascript:` links are removed.
final class MarkdownRenderer {
  const MarkdownRenderer();

  String toHtml(String source) =>
      sanitizeHtml(markdown.markdownToHtml(source, extensionSet: markdown.ExtensionSet.gitHubWeb));
}
