import { useState } from 'react'
import { BadgeCheck, EyeOff, Hourglass, Package } from 'lucide-react'
import {
  ContentCard,
  DetailsButton,
  DetailsHead,
  EmptyState,
  ErrorState,
  FilterChips,
  NameCell,
  PageIntro,
  Pager,
  ProductBadge,
  SearchBar,
  StatCard,
  StatRow,
  TableSkeleton,
  Thumb,
  card,
  pillSelect,
  row,
  showList,
  td,
  th,
  usePage,
} from '@/components/blocks'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { listCategories } from '@/data/categories'
import { listProducts, type ProductFilter } from '@/data/products'
import { money, number } from '@/lib/format'
import { useI18n } from '@/lib/i18n'
import { useSheet, useUrlFilters } from '@/lib/url-state'
import { useDebounced, useQuery } from '@/lib/use-query'
import { cn } from '@/lib/utils'

const FILTERS: ProductFilter[] = ['PENDING', 'APPROVED', 'REJECTED', 'TAKEN_DOWN']
const ALL = 'all'

export function ProductsPage() {
  const { t, lang, pick } = useI18n()
  const sheet = useSheet()
  const [q, setQ] = useState('')
  const [filters, setFilters] = useUrlFilters({ status: FILTERS })
  const status = filters.status as ProductFilter | ''
  const setStatus = (next: ProductFilter | '') => setFilters({ status: next })
  const [category, setCategory] = useState(ALL)
  const search = useDebounced(q)
  const categoryId = category === ALL ? undefined : category

  // The cards count the whole list; the counts are the same on every page, so one row is enough.
  const all = useQuery(() => listProducts({ page: 1, perPage: 1 }), 'products:all')
  const categories = useQuery(listCategories, 'categories')
  const [page, setPage] = usePage(`${search}:${status}:${category}`)
  const list = useQuery(
    () => listProducts({ q: search, status: status || undefined, categoryId, page }),
    `products:${search}:${status}:${category}:${page}`,
  )
  const counts = all.data?.counts
  const stat = (n?: number) => (all.error ? '—' : n)
  const filtered = !!(q || status || categoryId)
  /** A card shows exactly what it counted: its status, no search, every category. */
  const fromCard = (next: ProductFilter | '') => () => {
    setQ('')
    setCategory(ALL)
    setStatus(next)
    showList()
  }

  return (
    <>
      <PageIntro>{t.products.intro}</PageIntro>
      <StatRow>
        <StatCard label={t.products.total} value={stat(counts?.all)} icon={Package} onClick={fromCard('')} active={!status} />
        <StatCard
          label={t.products.waiting}
          value={stat(counts && (counts.PENDING ?? 0))}
          icon={Hourglass}
          onClick={fromCard('PENDING')}
          active={status === 'PENDING'}
        />
        <StatCard
          label={t.products.approved}
          value={stat(counts && (counts.APPROVED ?? 0))}
          icon={BadgeCheck}
          onClick={fromCard('APPROVED')}
          active={status === 'APPROVED'}
        />
        <StatCard
          label={t.products.takenDown}
          value={stat(counts && (counts.TAKEN_DOWN ?? 0))}
          icon={EyeOff}
          onClick={fromCard('TAKEN_DOWN')}
          active={status === 'TAKEN_DOWN'}
        />
      </StatRow>

      <ContentCard id="list" icon={Package} title={t.products.cardTitle} description={t.products.cardText}>
        <div className="space-y-4">
          <SearchBar value={q} onChange={setQ} placeholder={t.products.search} />
          <div className="flex flex-wrap items-center justify-between gap-3">
            <FilterChips
              label={t.col.status}
              value={status}
              onChange={setStatus}
              chips={[
                { value: '', label: t.all, count: list.data?.counts.all },
                ...FILTERS.map((s) => ({ value: s, label: t.productStatus[s], count: list.data && (list.data.counts[s] ?? 0) })),
              ]}
            />
            <Select value={category} onValueChange={setCategory}>
              <SelectTrigger
                aria-label={t.col.category}
                className={cn(pillSelect, 'min-w-52', categoryId && 'border-primary text-primary')}
              >
                <SelectValue />
              </SelectTrigger>
              <SelectContent position="popper" align="end" className="rounded-xl">
                <SelectItem value={ALL}>{t.products.allCategories}</SelectItem>
                {categories.data?.map((top) => (
                  <SelectGroup key={top.id}>
                    <SelectItem value={top.id} className="font-medium">
                      {pick(top.name, top.nameAr)}
                    </SelectItem>
                    {top.children.map((child) => (
                      <SelectItem key={child.id} value={child.id} className="ps-6 text-muted-foreground">
                        {pick(child.name, child.nameAr)}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        <div className="mt-6">
          {list.error ? (
            <ErrorState error={list.error} onRetry={list.retry} />
          ) : !list.data ? (
            <TableSkeleton columns={4} />
          ) : list.data.items.length === 0 ? (
            <EmptyState
              icon={Package}
              title={t.empty.search}
              text={t.empty.searchText}
              action={
                filtered && (
                  <Button
                    variant="outline"
                    className="h-10 rounded-full px-5"
                    onClick={() => (setQ(''), setStatus(''), setCategory(ALL))}
                  >
                    {t.clearFilters}
                  </Button>
                )
              }
            />
          ) : (
            <Table className={cn('transition-opacity', card.table, list.loading && 'opacity-60')}>
              <TableHeader>
                <TableRow className="border-border hover:bg-transparent">
                  <TableHead className={th}>{t.col.product}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.col.stock}</TableHead>
                  <TableHead className={cn(th, 'text-end')}>{t.col.price}</TableHead>
                  <TableHead className={th}>{t.col.status}</TableHead>
                  <DetailsHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.data.items.map((p) => (
                  <TableRow key={p.id} className={row} onClick={() => sheet.open('product', p.id)}>
                    <TableCell className={cn(td, 'max-w-[420px]')}>
                      <NameCell
                        thumb={<Thumb src={p.imageUrl} name={p.nameEn} />}
                        title={pick(p.nameEn, p.nameAr)}
                        subtitle={
                          <>
                            <bdi>{p.merchant.storeName}</bdi> · {pick(p.categoryName, p.categoryNameAr)}
                          </>
                        }
                      />
                    </TableCell>
                    <TableCell
                      className={cn(
                        td,
                        card.hide,
                        'text-end text-[15px] tabular-nums',
                        p.stockStatus === 'OUT_OF_STOCK' ? 'text-bad' : p.stockStatus === 'LOW_STOCK' ? 'text-wait' : 'text-navy',
                      )}
                    >
                      {number(p.availableQuantity)}
                    </TableCell>
                    <TableCell className={cn(td, card.line, 'text-end')}>
                      <div className="text-[15px] font-medium text-navy tabular-nums">{money(p.price, lang)}</div>
                      {p.originalPrice !== undefined && (
                        <div className="text-[13px] text-faint line-through tabular-nums">{money(p.originalPrice, lang)}</div>
                      )}
                    </TableCell>
                    <TableCell className={td}>
                      <ProductBadge product={p} />
                    </TableCell>
                    <TableCell className={cn(td, card.end, 'text-end')}>
                      <DetailsButton onClick={() => sheet.open('product', p.id)} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
        <Pager
          meta={list.data?.meta}
          busy={list.loading}
          onPage={(next) => {
            setPage(next)
            showList()
          }}
        />
      </ContentCard>
    </>
  )
}
