import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/app_routes.dart';
import '../theme/app_dimensions.dart';
import '../theme/saba_icons.dart';
import '../utils/context_extensions.dart';
import 'search_pill.dart';

/// The row that starts every browsing screen: search, and the list you build
/// while you shop.
///
/// The wishlist used to live in Account, in the card under "Change password".
/// It is not a setting — you reach for it in the middle of looking at things,
/// and walking to Account to do it means leaving what you were looking at.
/// Here it sits where the shopping happens.
class ShopHeader extends ConsumerWidget {
  const ShopHeader({super.key, this.hint, this.showWishlist = true});

  /// Each screen says what searching it means; Browse searches stores too.
  final String? hint;

  /// The heart beside the search. Home leaves it out: the wishlist is a row
  /// in Account and a heart on every product.
  final bool showWishlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Row(
        children: [
          Expanded(
            child: SearchPill(
              hint: hint ?? l10n.searchPlaceholder,
              onTap: () => context.push(AppRoutes.search),
            ),
          ),
          if (showWishlist) ...[
            const SizedBox(width: AppSpacing.sm),
            CircleIconButton(
              icon: SabaIcons.heart,
              tooltip: l10n.wishlist,
              onPressed: () => context.push(AppRoutes.wishlist),
            ),
          ],
        ],
      ),
    );
  }
}
