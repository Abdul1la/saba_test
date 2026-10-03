import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/saba_icons.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../messaging_providers.dart';

/// A chat photo, full size, on black, with pinch-to-zoom. The signed link is
/// good for an hour or two; if it has expired by the time it is opened, the
/// thread is reloaded for fresh links and the picture reappears.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({super.key, required this.url, this.conversationId});

  final String url;

  /// The chat to reload for fresh links when this one has expired.
  final String? conversationId;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late String _url = widget.url;
  bool _reloaded = false;

  /// The link may have expired (404). Reload the thread once for fresh ones
  /// and find this photo's new link; a data URL (the demo) never expires.
  Future<void> _refreshLink() async {
    final id = widget.conversationId;
    if (_reloaded || id == null || _url.startsWith('data:')) return;
    _reloaded = true;
    await ref.read(conversationProvider(id).notifier).refresh();
    if (!mounted) return;
    final fresh = ref
        .read(conversationProvider(id))
        .value
        ?.where((m) => m.isPhoto && m.photoUrl != null)
        .toList();
    // Only one photo in the usual thread, so the newest live link is it; a
    // richer match would need an id the bubble does not carry yet.
    if (fresh != null && fresh.isNotEmpty) {
      setState(() => _url = fresh.last.photoUrl!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No app bar: a photo fills the black, and a close button sits over it.
    // Material's AppBar is kept out of the screens by the design-system guard.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: AppNetworkImage(
                key: ValueKey(_url),
                url: _url,
                fit: BoxFit.contain,
                radius: 0,
                // A broken link gets one reload, then the fallback.
                fallback: _ExpiredPhoto(onVisible: _refreshLink),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            start: 0,
            child: SafeArea(
              child: IconButton(
                icon: SabaIcon(
                  SabaIcons.close,
                  size: AppSizes.iconMd,
                  color: Colors.white,
                ),
                tooltip: context.l10n.close,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drawn when the photo will not load; asks the thread for a fresh link once.
class _ExpiredPhoto extends StatefulWidget {
  const _ExpiredPhoto({required this.onVisible});

  final VoidCallback onVisible;

  @override
  State<_ExpiredPhoto> createState() => _ExpiredPhotoState();
}

class _ExpiredPhotoState extends State<_ExpiredPhoto> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onVisible());
  }

  @override
  Widget build(BuildContext context) {
    return SabaIcon(
      SabaIcons.imageOff,
      size: AppSizes.iconLg,
      color: Colors.white54,
    );
  }
}
