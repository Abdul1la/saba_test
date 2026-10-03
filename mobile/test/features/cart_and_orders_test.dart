import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/features/cart/domain/entities.dart';
import 'package:saba_marketplace/features/catalog/domain/entities.dart';
import 'package:saba_marketplace/features/orders/domain/entities.dart';

CartItem _item({
  required String id,
  int quantity = 1,
  StockStatus status = StockStatus.inStock,
}) {
  return CartItem(
    id: id,
    productId: 'p-$id',
    name: 'Item $id',
    unitPrice: 10,
    quantity: quantity,
    lineTotal: 10 * quantity,
    currencyCode: 'USD',
    stockStatus: status,
  );
}

CartMerchantGroup _group(String merchantId, List<CartItem> items) {
  return CartMerchantGroup(
    merchantId: merchantId,
    merchantName: 'Store $merchantId',
    items: items,
    subtotal: items.fold<num>(0, (total, item) => total + item.lineTotal),
    currencyCode: 'USD',
  );
}

void main() {
  group('Cart', () {
    test('counts units across every merchant group', () {
      final cart = Cart(
        id: 'c1',
        groups: [
          _group('m1', [_item(id: 'a', quantity: 2), _item(id: 'b')]),
          _group('m2', [_item(id: 'c', quantity: 3)]),
        ],
        totals: const CartTotals(subtotal: 60, total: 60, currencyCode: 'USD'),
      );

      expect(cart.itemCount, 6);
      expect(cart.merchantCount, 2);
      expect(cart.allItems, hasLength(3));
    });

    test('blocks checkout while any line is out of stock', () {
      final cart = Cart(
        id: 'c1',
        groups: [
          _group('m1', [
            _item(id: 'a'),
            _item(id: 'b', status: StockStatus.outOfStock),
          ]),
        ],
        totals: const CartTotals(subtotal: 20, total: 20, currencyCode: 'USD'),
      );

      expect(cart.hasUnavailableItems, isTrue);
      expect(cart.canCheckout, isFalse);
    });

    test('allows checkout when everything is purchasable', () {
      final cart = Cart(
        id: 'c1',
        groups: [
          _group('m1', [
            _item(id: 'a'),
            _item(id: 'b', status: StockStatus.lowStock),
          ]),
        ],
        totals: const CartTotals(subtotal: 20, total: 20, currencyCode: 'USD'),
      );

      expect(cart.canCheckout, isTrue);
    });

    test('an empty cart cannot be checked out', () {
      const cart = Cart.empty();
      expect(cart.isEmpty, isTrue);
      expect(cart.canCheckout, isFalse);
      expect(cart.itemCount, 0);
    });
  });

  group('StockStatus', () {
    test('derives status from quantity when the server omits it', () {
      expect(StockStatus.fromApi(null, quantity: 0), StockStatus.outOfStock);
      expect(StockStatus.fromApi(null, quantity: 5), StockStatus.inStock);
      expect(
        StockStatus.fromApi(null, quantity: 2, threshold: 3),
        StockStatus.lowStock,
      );
    });

    test('an explicit status from the server wins', () {
      expect(
        StockStatus.fromApi('OUT_OF_STOCK', quantity: 99),
        StockStatus.outOfStock,
      );
    });

    test('only in-stock and low-stock are purchasable', () {
      expect(StockStatus.inStock.isPurchasable, isTrue);
      expect(StockStatus.lowStock.isPurchasable, isTrue);
      expect(StockStatus.outOfStock.isPurchasable, isFalse);
      expect(StockStatus.unknown.isPurchasable, isFalse);
    });
  });

  group('Product variants', () {
    final product = Product(
      id: 'p1',
      name: 'Phone',
      price: 100,
      currencyCode: 'USD',
      stockStatus: StockStatus.inStock,
      variantOptions: const {
        'Color': ['Black', 'Blue'],
        'Storage': ['128GB', '256GB'],
      },
      variants: const [
        ProductVariant(
          id: 'v1',
          price: 100,
          stockStatus: StockStatus.inStock,
          options: {'Color': 'Black', 'Storage': '128GB'},
        ),
        ProductVariant(
          id: 'v2',
          price: 120,
          stockStatus: StockStatus.outOfStock,
          options: {'Color': 'Black', 'Storage': '256GB'},
        ),
      ],
    );

    test('resolves the variant matching a complete selection', () {
      final variant = product.variantFor({
        'Color': 'Black',
        'Storage': '256GB',
      });

      expect(variant?.id, 'v2');
      expect(variant?.price, 120);
      expect(variant?.isAvailable, isFalse);
    });

    test('returns null for a partial selection', () {
      expect(product.variantFor({'Color': 'Black'}), isNull);
    });

    test('returns null when no variant matches', () {
      expect(product.variantFor({'Color': 'Blue', 'Storage': '512GB'}), isNull);
    });
  });

  group('Order', () {
    test('groups items by the merchant that fulfils them', () {
      final order = Order(
        id: 'o1',
        orderNumber: 'SB-1',
        placedAt: DateTime(2026),
        status: OrderStatus.processing,
        paymentStatus: PaymentStatus.paid,
        subtotal: 30,
        total: 30,
        currencyCode: 'USD',
        items: const [
          OrderItem(
            id: 'i1',
            productName: 'A',
            quantity: 1,
            unitPrice: 10,
            lineTotal: 10,
            currencyCode: 'USD',
            merchantName: 'Store One',
          ),
          OrderItem(
            id: 'i2',
            productName: 'B',
            quantity: 2,
            unitPrice: 10,
            lineTotal: 20,
            currencyCode: 'USD',
            merchantName: 'Store One',
          ),
          OrderItem(
            id: 'i3',
            productName: 'C',
            quantity: 1,
            unitPrice: 10,
            lineTotal: 10,
            currencyCode: 'USD',
            merchantName: 'Store Two',
          ),
        ],
      );

      expect(order.itemsByMerchant.keys, ['Store One', 'Store Two']);
      expect(order.itemsByMerchant['Store One'], hasLength(2));
      expect(order.itemCount, 4);
    });

    test('status parsing accepts backend synonyms', () {
      expect(OrderStatus.fromApi('NEW'), OrderStatus.pending);
      expect(OrderStatus.fromApi('IN_TRANSIT'), OrderStatus.shipped);
      expect(OrderStatus.fromApi('COMPLETED'), OrderStatus.delivered);
      expect(OrderStatus.fromApi('nonsense'), OrderStatus.unknown);
    });

    test('terminal statuses are recognised', () {
      expect(OrderStatus.delivered.isTerminal, isTrue);
      expect(OrderStatus.refunded.isTerminal, isTrue);
      expect(OrderStatus.processing.isTerminal, isFalse);
    });

    test('payment status parsing accepts provider synonyms', () {
      expect(PaymentStatus.fromApi('CAPTURED'), PaymentStatus.paid);
      expect(PaymentStatus.fromApi('SUCCEEDED'), PaymentStatus.paid);
      expect(
        PaymentStatus.fromApi('PARTIALLY_REFUNDED'),
        PaymentStatus.partiallyRefunded,
      );
    });
  });
}
