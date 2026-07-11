import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

/// Renders sanitized article HTML as Flutter widgets: paragraphs, headings,
/// lists, quotes, code blocks, images, and tappable links. Scripts, styles,
/// forms, and embeds are dropped; unknown tags fall back to their text.
class ArticleHtmlView extends StatefulWidget {
  const ArticleHtmlView({super.key, required this.html, this.baseUrl});

  final String html;

  /// Used to resolve relative image and link URLs.
  final Uri? baseUrl;

  @override
  State<ArticleHtmlView> createState() => _ArticleHtmlViewState();
}

class _ArticleHtmlViewState extends State<ArticleHtmlView> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final fragment = html_parser.parseFragment(widget.html);
    final blocks = _Renderer(this, context).renderBlocks(fragment.nodes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  TapGestureRecognizer _linkRecognizer(Uri url) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => launchUrl(url, mode: LaunchMode.externalApplication);
    _recognizers.add(recognizer);
    return recognizer;
  }
}

const Set<String> _droppedTags = {
  'script',
  'style',
  'noscript',
  'form',
  'input',
  'button',
  'svg',
  'template',
  'head',
};

const Set<String> _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'main',
  'header',
  'footer',
  'aside',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'li',
  'blockquote',
  'pre',
  'figure',
  'figcaption',
  'img',
  'hr',
  'table',
  'iframe',
  'video',
  'audio',
};

class _Renderer {
  _Renderer(this._state, this._context);

  final _ArticleHtmlViewState _state;
  final BuildContext _context;

  ThemeData get _theme => Theme.of(_context);
  ColorScheme get _colors => _theme.colorScheme;
  TextStyle get _body =>
      _theme.textTheme.bodyLarge?.copyWith(height: 1.6) ?? const TextStyle();

  List<Widget> renderBlocks(List<dom.Node> nodes) {
    final blocks = <Widget>[];
    final inlineRun = <dom.Node>[];

    void flushInline() {
      if (inlineRun.isEmpty) {
        return;
      }
      final span = _inlineSpan(List.of(inlineRun), _body);
      inlineRun.clear();
      if (_spanHasContent(span)) {
        blocks
          ..add(Text.rich(TextSpan(children: [span]), style: _body))
          ..add(const SizedBox(height: 12));
      }
    }

    for (final node in nodes) {
      if (node is dom.Element && _droppedTags.contains(node.localName)) {
        continue;
      }
      if (node is dom.Element && _blockTags.contains(node.localName)) {
        flushInline();
        blocks.addAll(_renderBlockElement(node));
      } else {
        inlineRun.add(node);
      }
    }
    flushInline();
    if (blocks.isNotEmpty && blocks.last is SizedBox) {
      blocks.removeLast();
    }
    return blocks;
  }

  List<Widget> _renderBlockElement(dom.Element element) {
    switch (element.localName) {
      case 'h1' || 'h2':
        return _paragraph(
          element,
          _theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        );
      case 'h3' || 'h4' || 'h5' || 'h6':
        return _paragraph(
          element,
          _theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        );
      case 'ul' || 'ol':
        return _list(element);
      case 'li':
        return _listItem(element, '-');
      case 'blockquote':
        return [
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: _colors.primary, width: 3),
              ),
              color: _colors.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: renderBlocks(element.nodes),
            ),
          ),
        ];
      case 'pre':
        final code = element.text.trimRight();
        if (code.isEmpty) {
          return const [];
        }
        return [
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: _colors.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                code,
                style: _theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ];
      case 'img':
        return _image(element);
      case 'figure':
        return renderBlocks(element.nodes);
      case 'figcaption':
        return _paragraph(
          element,
          _theme.textTheme.bodySmall?.copyWith(
            color: _colors.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        );
      case 'hr':
        return [Divider(color: _colors.outlineVariant, height: 24)];
      case 'iframe' || 'video' || 'audio':
        return _embedPlaceholder(element);
      case 'table':
        // Tables are rare in feeds; keep their text readable.
        return _paragraph(element, _body);
      default:
        return renderBlocks(element.nodes);
    }
  }

  List<Widget> _paragraph(dom.Element element, TextStyle? style) {
    final effective = style ?? _body;
    final span = _inlineSpan(element.nodes, effective);
    if (!_spanHasContent(span)) {
      return const [];
    }
    return [
      Text.rich(TextSpan(children: [span]), style: effective),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _list(dom.Element element) {
    final ordered = element.localName == 'ol';
    final items = element.children
        .where((child) => child.localName == 'li')
        .toList(growable: false);
    final widgets = <Widget>[];
    for (var index = 0; index < items.length; index += 1) {
      widgets.addAll(_listItem(items[index], ordered ? '${index + 1}.' : '-'));
    }
    if (widgets.isNotEmpty) {
      widgets.add(const SizedBox(height: 4));
    }
    return widgets;
  }

  List<Widget> _listItem(dom.Element element, String marker) {
    final children = renderBlocks(element.nodes);
    if (children.isEmpty) {
      return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$marker ', style: _body.copyWith(color: _colors.primary)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _image(dom.Element element) {
    final source =
        element.attributes['src'] ??
        element.attributes['data-src'] ??
        element.attributes['data-lazy-src'];
    final resolved = _resolveUrl(source);
    if (resolved == null) {
      return const [];
    }
    final alt = element.attributes['alt']?.trim();
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            resolved.toString(),
            fit: BoxFit.contain,
            // Cross-origin images without CORS headers cannot be decoded by
            // the web renderer; fall back to a platform <img> element.
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (context, error, stackTrace) => Container(
              padding: const EdgeInsets.all(12),
              color: _colors.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(
                    Icons.image_not_supported_outlined,
                    size: 18,
                    color: _colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alt == null || alt.isEmpty ? 'Image unavailable' : alt,
                      style: _theme.textTheme.bodySmall?.copyWith(
                        color: _colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _embedPlaceholder(dom.Element element) {
    final source = _resolveUrl(element.attributes['src']);
    final label = switch (element.localName) {
      'video' => 'Video',
      'audio' => 'Audio',
      _ => 'Embedded content',
    };
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: source == null
              ? null
              : () => launchUrl(source, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(
            source == null ? '$label (unavailable offline)' : 'Open $label',
          ),
        ),
      ),
    ];
  }

  TextSpan _inlineSpan(List<dom.Node> nodes, TextStyle style) {
    final children = <InlineSpan>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isNotEmpty) {
          children.add(TextSpan(text: text, style: style));
        }
        continue;
      }
      if (node is! dom.Element) {
        continue;
      }
      if (_droppedTags.contains(node.localName)) {
        continue;
      }
      switch (node.localName) {
        case 'br':
          children.add(const TextSpan(text: '\n'));
        case 'b' || 'strong':
          children.add(
            _inlineSpan(
              node.nodes,
              style.copyWith(fontWeight: FontWeight.w700),
            ),
          );
        case 'i' || 'em' || 'cite':
          children.add(
            _inlineSpan(
              node.nodes,
              style.copyWith(fontStyle: FontStyle.italic),
            ),
          );
        case 'code' || 'kbd' || 'samp':
          children.add(
            _inlineSpan(
              node.nodes,
              style.copyWith(
                fontFamily: 'monospace',
                backgroundColor: _colors.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
              ),
            ),
          );
        case 'a':
          final url = _resolveUrl(node.attributes['href']);
          final linkStyle = style.copyWith(
            color: _colors.primary,
            decoration: TextDecoration.underline,
            decorationColor: _colors.primary.withValues(alpha: 0.5),
          );
          children.add(
            url == null
                ? _inlineSpan(node.nodes, linkStyle)
                : TextSpan(
                    children: [_inlineSpan(node.nodes, linkStyle)],
                    recognizer: _state._linkRecognizer(url),
                  ),
          );
        case 'img':
          final alt = node.attributes['alt']?.trim();
          if (alt != null && alt.isNotEmpty) {
            children.add(TextSpan(text: '[$alt]', style: style));
          }
        default:
          children.add(_inlineSpan(node.nodes, style));
      }
    }
    return TextSpan(children: children);
  }

  Uri? _resolveUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null) {
      return null;
    }
    final resolved = _resolveAgainstBase(parsed);
    if (!resolved.hasScheme ||
        (resolved.scheme != 'http' && resolved.scheme != 'https')) {
      return null;
    }
    return resolved;
  }

  Uri _resolveAgainstBase(Uri parsed) {
    final base = _state.widget.baseUrl;
    return base == null ? parsed : base.resolveUri(parsed);
  }
}

bool _spanHasContent(InlineSpan span) {
  var hasContent = false;
  span.visitChildren((child) {
    if (child is TextSpan && (child.text?.trim().isNotEmpty ?? false)) {
      hasContent = true;
      return false;
    }
    return true;
  });
  return hasContent;
}
