import * as XLSX from 'xlsx'
import type { RowData, Table, TableFeatures } from '@tanstack/svelte-table'

/**
 * Export the table's currently-filtered rows to an `.xlsx` file.
 *
 * Labels and values are read from each column's `meta.export` (see
 * table-meta.d.ts). This keeps the spreadsheet in lock-step with the column
 * definitions — there is no second hand-maintained mapping to drift out of
 * sync. Columns without `meta.export` are simply excluded from the file.
 *
 *   {
 *     accessorKey: 'fechaInsert',
 *     header: ...,
 *     cell: ...,
 *     meta: { export: { label: 'Fecha', value: r => formatDate(r.fechaInsert, 'dd-MM-yyyy') } },
 *   }
 *
 * The export reflects active column filters and global search (filtered row
 * model), but always includes every `meta.export` column regardless of whether
 * it is currently hidden — a hidden column is still real data worth exporting.
 *
 * @param table   the tanstack table instance
 * @param opts.filename   base name; a `_YYYYMMDD` suffix and `.xlsx` are appended
 * @param opts.sheetName  worksheet name (default `'Data'`)
 */
export function exportTableXlsx<TFeatures extends TableFeatures, TData extends RowData>(
  table: Table<TFeatures, TData>,
  opts: { filename: string; sheetName?: string }
) {
  const cols = table
    .getAllLeafColumns()
    .map(c => (c.columnDef.meta as {export?: {label: string; value: (row: TData) => string | number | boolean | null | undefined}} | undefined)?.export)
    .filter((e): e is NonNullable<typeof e> => !!e)

  if (cols.length === 0) {
    console.warn('[exportTableXlsx] no columns declare `meta.export` — nothing to export')
    return
  }

  const rows = table.getFilteredRowModel().rows.map(r => r.original)
  const sheetData = rows.map(row => {
    const record: Record<string, unknown> = {}
    for (const col of cols) record[col.label] = col.value(row) ?? ''
    return record
  })

  const ws = XLSX.utils.json_to_sheet(sheetData)
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, opts.sheetName ?? 'Data')

  const d = new Date()
  const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`
  XLSX.writeFile(wb, `${opts.filename}_${ymd}.xlsx`)
}
