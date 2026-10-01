/**
 * Augments tanstack's `ColumnMeta` so column definitions can carry the
 * spreadsheet-export config consumed by `exportTableXlsx` (table-export.ts).
 *
 * Drop this file next to table-prefs/table-export (e.g. in
 * `src/lib/components/ui/data-table/`). TypeScript picks it up automatically;
 * nothing imports it.
 *
 * v9: the interface takes TFeatures first. Alternatively, type meta per-table
 * with the `columnMeta` slot on `tableFeatures()` — no declaration merging.
 */
import type { RowData, TableFeatures } from '@tanstack/svelte-table'

declare module '@tanstack/svelte-table' {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  interface ColumnMeta<TFeatures extends TableFeatures, TData extends RowData, TValue> {
    /** Spreadsheet-export config. Omit a column's `export` to leave it out of the file. */
    export?: {
      /** Header text for this column in the `.xlsx`. */
      label: string
      /** Plain-text/number value for a given row. */
      value: (row: TData) => string | number | boolean | null | undefined
    }
  }
}

export {}