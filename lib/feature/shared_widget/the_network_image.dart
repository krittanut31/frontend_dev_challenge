import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Standard network image with a shimmer placeholder.
class TheNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const TheNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Decode at the size the image is drawn, not the source size: the API
      // serves 1600x1200 photos (~7.7 MB each once decoded) into 160px-tall
      // cards. Only one side is set so the aspect ratio is kept.
      final dpr = MediaQuery.devicePixelRatioOf(context);
      // `width: double.infinity` means "fill", so fall back to constraints.
      final drawWidth =
          (width?.isFinite ?? false) ? width! : constraints.maxWidth;
      final drawHeight =
          (height?.isFinite ?? false) ? height! : constraints.maxHeight;
      final byWidth = drawWidth.isFinite &&
          (!drawHeight.isFinite || drawWidth >= drawHeight);
      return _buildImage(
        memCacheWidth: byWidth ? (drawWidth * dpr).round() : null,
        memCacheHeight: !byWidth && drawHeight.isFinite
            ? (drawHeight * dpr).round()
            : null,
      );
    });
  }

  Widget _buildImage({int? memCacheWidth, int? memCacheHeight}) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        placeholder: (context, _) => Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(width: width, height: height, color: Colors.white),
        ),
        errorWidget: (context, _, __) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported_outlined),
        ),
      ),
    );
  }
}
