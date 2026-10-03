// What a shopper pays, worked out when it is read (DATABASE_DESIGN.md §3.3):
// an ended flash sale is never sold, and nothing has to run on a clock.
// Whole IQD throughout.

export interface ProductPrices {
  base_price: number
  compare_at_price: number | null
  sale_price: number | null
  sale_ends_at: Date | null
}

export interface Shown {
  price: number
  originalPrice: number | null
  discountPercentage: number | null
}

/** A flash sale is on while its end is in the future. */
export function saleIsOn(product: ProductPrices, now: Date): boolean {
  return product.sale_price !== null && product.sale_ends_at !== null && product.sale_ends_at > now
}

/** What the running sale takes off every price of the product; 0 without one. */
export function saleOff(product: ProductPrices, now: Date): number {
  return saleIsOn(product, now) ? product.base_price - product.sale_price! : 0
}

function shown(price: number, originalPrice: number | null): Shown {
  return {
    price,
    originalPrice,
    discountPercentage: originalPrice === null ? null : Math.round((1 - price / originalPrice) * 100),
  }
}

/** The product's own price: the sale price during a sale, else the normal one beside any lasting original. */
export function productPrice(product: ProductPrices, now: Date): Shown {
  return saleIsOn(product, now)
    ? shown(product.sale_price!, product.base_price)
    : shown(product.base_price, product.compare_at_price)
}

/**
 * An option's price ([optionPrice] is its normal one): the sale's discount
 * off it during a sale; with a lasting discount, its original is its price
 * plus the product's markdown (the seed's `_variantsFor`, `_startSale`).
 */
export function optionPrice(product: ProductPrices, optionPrice: number, now: Date): Shown {
  if (saleIsOn(product, now)) return shown(optionPrice - saleOff(product, now), optionPrice)
  const markdown = product.compare_at_price === null ? null : product.compare_at_price - product.base_price
  return shown(optionPrice, markdown === null ? null : optionPrice + markdown)
}

export type StockStatus = 'IN_STOCK' | 'LOW_STOCK' | 'OUT_OF_STOCK'

/** 0 is out, 1–5 low, 6 and up in stock (the demo's `_stockStatus`). */
export function stockStatus(stock: number): StockStatus {
  return stock <= 0 ? 'OUT_OF_STOCK' : stock <= 5 ? 'LOW_STOCK' : 'IN_STOCK'
}

export const LOW_STOCK_AT_MOST = 5
