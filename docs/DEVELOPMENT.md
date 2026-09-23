# Development

## Layout

The plugin manifest points to `qml/Service.qml` and `qml/BarWidget.qml`.
`qml/StocksWindow.qml` composes the application; `qml/SettingsMenu.qml` manages
display preferences.

| Directory | Responsibility |
|---|---|
| `qml/stores/` | Watchlists, selection, quotes, research and comparison state |
| `qml/data/` | Debounced requests, bulk symbol sets and bounded per-stock batches |
| `qml/components/` | Shared controls, tables, loading indicators and headers |
| `qml/charts/` | Price/metric charts, chart controls and pure chart math |
| `qml/stock/` | Company research, news, social feeds and fundamental comparison |
| `qml/market/` | Market dashboard, treemaps, sentiment, calendar and session clock |
| `qml/watchlist/` | List editing/sorting, Overview, earnings calendar and page host |
| `qml/art/` | Candlestick logo, pixel sprites and header animation |
| `bin/` | Standard-library Python helpers and provider adapters |
| `assets/` | Desktop launcher and icon |
| `data/` | Static membership snapshots; see [provenance](../data/README.md) |
| `tests/` | Backend and pure JavaScript regression tests |
| `docs/screenshots/` | Current UI gallery; the root `preview.png` is the cover |

### QML imports

`qml/qmldir` registers the entire UI as one directory module, including the two
singletons. Feature components import `".."`; top-level components import `"."`.
Keep registrations here so every feature shares the same stores. JavaScript
imports are relative to the component using them. The helper paths in
`qml/data/DataRequest.qml` and `qml/stores/StockStore.qml` resolve back to `bin/`.

Use Omarchy's `qs.Commons` tokens for theme and spacing, and `Ui.PanelToolTip` for
tooltips. Financial direction stays green (`#4caf50`) or red (`#ef5350`) across themes.

## Data flow

- `bin/stocks.py` serializes watchlist mutations and chart/quote storage with a
  file lock and atomic writes. Named lists are normalized by `bin/watchlists.py`;
  `entries` remains the active-list mirror in `watchlist.json`.
- `bin/research.py` handles independent research requests, per-request locks,
  cache schemas and TTLs. A failed refresh preserves the last result and gets a
  short retry cooldown. `DataRequest.qml` rejects obsolete replies and owns polling.
- Watchlist live quotes and market-wide quotes have separate bulk requests.
  Market quotes persist across watchlist/tab changes. Historical Overview
  baselines refresh daily rather than with every live-price refresh.
- Market memberships are local snapshots. Index/sector maps use bulk requests;
  they never fan an entire membership into per-symbol charts. Research batches
  have four workers. Market pages stay mounted after the first visit and poll
  only while active.
- `bin/yahoo_http.py` shares anonymous authentication, request pacing and HTTP 429
  backoff across helper processes. Manual refresh bypasses ordinary caches and
  failure cooldowns, while respecting that shared throttle and successful daily
  Overview baselines. `bin/tradingview.py` shares bounded scanner transport and
  share-class symbol mapping.

Network hosts: `query1.finance.yahoo.com`, `finance.yahoo.com`, `fc.yahoo.com`,
`api.nasdaq.com`, `scanner.tradingview.com`, `economic-calendar.tradingview.com`,
`production.dataviz.cnn.io`, `news.google.com`, `www.google.com`,
`api.stocktwits.com`, and `apewisdom.io`. Thumbnails use provider-supplied image URLs;
source links open externally. The earnings-release helper resolves Google's
redirect on demand. Yahoo's anonymous cookies and crumb stay in the local state directory.

## Checks

From the repository root:

```sh
python3 -m unittest discover -s tests -v
node tests/test_chart.cjs
node tests/test_treemap.cjs
node tests/test_watchlist_order.cjs
node tests/test_pixel_art.cjs
node tests/test_market_assets.cjs
bash -n install install-launcher uninstall
omarchy plugin validate .
git diff --check
```

Node.js is a test dependency only. For helper/UI experiments, set
`STOCKS_STATE_DIR` to an isolated test directory. Keep test state separate from
your live watchlists.

After QML changes, reload and reopen:

```sh
omarchy restart shell
omarchy-shell io.github.dmitry-solomadin.omastocks open
omarchy-shell io.github.dmitry-solomadin.omastocks status
```

Check Stock, Market and Watchlist; test chart comparison, list selection and settings
at compact and wide window sizes. Close/reopen using both the compositor and
`Ctrl+W`. For new screenshots, capture the current rendered app after its data
loads; keep the cover and gallery consistent with the current branch.
