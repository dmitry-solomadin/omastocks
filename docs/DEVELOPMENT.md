# Development

## Development checkout

For an editable checkout linked into your local Omarchy installation:

```sh
git clone https://github.com/dmitry-solomadin/omastocks
cd omastocks
./install
```

`./install` validates and symlinks this checkout into the user plugin directory,
then enables it. It refuses to replace a different existing installation.
No compilation is required.

## Layout

The plugin manifest points to `qml/Service.qml` and `qml/BarWidget.qml`.
`qml/StocksWindow.qml` composes the application; `qml/SettingsMenu.qml` manages
display preferences.

The service runs `install-launcher` on startup, so `omarchy plugin add … --enable`
also installs the desktop entry and icon. The installer updates changed assets
without rewriting identical files on each shell reload.
When the service unloads (disable, removal or reload), it cleans up its generated
launcher and icon. A lock and per-instance ownership token prevent an old instance
from removing a newer one's files. Cleanup uses the helper cached in memory so it
still works after `omarchy plugin remove` deletes the plugin folder. Watchlists and
research caches are outside this cleanup; `uninstall` is a compatibility wrapper
around the native removal command.

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

`qml/qmldir` registers the entire UI as one directory module, including the shared
state and theme singletons. Feature components import `".."`; top-level components import `"."`.
Keep registrations here so every feature shares the same stores. JavaScript
imports are relative to the component using them. The helper paths in
`qml/data/DataRequest.qml` and `qml/stores/StockStore.qml` resolve back to `bin/`.

Use Omarchy's `qs.Commons` tokens for theme and spacing, and `Ui.PanelToolTip` for
tooltips. Financial direction stays green (`#4caf50`) or red (`#ef5350`) across themes.

## Data flow

- `bin/stocks.py` serializes watchlist mutations and quote storage with a
  file lock and atomic writes. Named lists are normalized by `bin/watchlists.py`;
  `entries` remains the active-list mirror in `watchlist.json`.
- `bin/research.py` handles independent research requests, per-request locks,
  cache schemas and TTLs. A failed refresh preserves the last result and gets a
  short retry cooldown. Comparison lines (`compare`) and the extended-hours chart
  (`extended`) are the exception: like the primary chart, they are downloaded on
  every request and never saved. `DataRequest.qml` rejects obsolete replies and
  owns polling.
- The active watchlist and favorites across lists share bulk quote requests
  (up to 70 symbols each), also used by the sidebar and Watchlist Overview.
  Failed quotes retain saved values and retry after 1, 2, 4, 8… seconds, capped
  at 300 seconds; the UI schedules these deadlines independently of the regular
  poll. Recovery requests include only failed/due quotes.
  Success resets the backoff, and Yahoo's shared rate-limit cooldown takes
  precedence. A stock outside the watchlist gets its header quote from the same
  bulk request, not from its chart.
- Charts are live and never saved; `cache.json` holds only quotes and sparklines,
  and chart entries left by earlier versions are dropped. A failed refresh keeps
  only the chart already on screen, with "As of d MMM HH:mm · refresh failed" on
  the chart's top line opposite the chart options (the date matters: it may be
  an earlier day's). A chart not yet shown says "Chart unavailable · Refresh to
  retry". The comparison legend's tooltips carry the same note.
- The Stock view's charts come from one long-lived helper, `bin/chart_server.py`
  (a JSON line each way), which reuses Yahoo's HTTPS connection
  (`yahoo_http.KeepAlive`), and whose requests take their turn at once: about
  40–75 ms a chart when Yahoo's edge has it cached and about 150 ms when not,
  instead of about 230 ms for a new process. It takes no lock and saves nothing,
  so a chart never waits behind the watchlist queue. One chart runs at a time; a newer request replaces one
  waiting. If the helper dies, that chart is fetched by a one-shot
  `stocks.py chart` and the next chart restarts it; if it hangs for 45 seconds it
  is stopped and the chart fails like any refresh; after three failures in a row
  it rests for ten minutes while one-shot helpers fetch the charts. Closing the
  window stops it, and it exits by itself when its input closes. A connection
  idle for over a minute is replaced rather than reused, since one dropped by a
  suspend or network change would only fail after the timeout.
- One `StockStore` poll refreshes the quotes and the chart together, so the
  header, sidebar, bar ticker and chart never disagree. It runs every 60 seconds
  while a 1D chart is live and every five minutes otherwise, which also keeps the
  bar's quotes current while the window is closed. Live means the window is open
  and not minimized, the Stock view shows a stock, and that stock's quote reports
  its regular session (`REGULAR`, or no state). Pre-market and after hours leave
  the regular chart unchanged: only a shown Extended chart refreshes then, every
  60 seconds; otherwise the poll slows to five minutes for the quotes, which carry
  the extended-hours price. Only a live chart refreshes on the poll; any chart
  also loads once when it appears (opening or restoring the window, returning to
  the Stock view), when the regular session starts, and once when it ends, for
  the closing price.
  Quotes older than 30 seconds are refreshed, below the poll so none is skipped.
  `StockStore.requestChart` is the one place that asks for the chart; it skips a
  duplicate of the chart already running or waiting unless the user refreshes,
  and emits `chartRequested`, on which comparison lines and the extended chart
  reload. They therefore follow the chart's pace and are never older than it.
- The header's pre-market or after-hours price comes from the bulk quote
  (Yahoo's `preMarket*` and `postMarket*` fields), chosen by
  `StockStore.extendedQuote` once it is newer than the last regular trade, and
  refreshes with the poll at no extra cost. The Extended chart is fetched only
  while it is shown on 1D. Symbols without extended-hours data, from the quote's
  `hasPrePostMarketData` or a `supported: false` reply, are skipped for the
  session and their Extended button is greyed out.
- Sidebar sparklines and the bar's hover preview use Yahoo's bulk spark request
  (five-minute closes, up to 20 symbols each) with regular quote refreshes.
  Recovery retries skip it, and a failed request keeps each symbol's last line.
- Chart sampling uses one-minute candles for 1D (including extended hours).
  Its volume histogram groups those values into five-minute totals, while
  price-hover tooltips retain each minute's original volume. Yahoo ends
  intraday candles with its latest quote (live or closing price) and a
  placeholder zero volume. On 1D the quote keeps its price and time without a
  volume tooltip, and the five-minute bar in progress sums only its candles; on
  1W the half-hour bar the quote falls in, or closes, takes its price and keeps
  its own volume.
  1M requests hourly data and groups it into three exchange-session segments per
  day, retaining each segment's last close and summed volume. Provider session
  hours handle early closes; unfinished or sparse sessions can have fewer samples.
  Other ranges retain their existing intervals. Comparison charts use the same
  sampling; daily moving averages on 1M use completed-day values for earlier
  intraday samples. Moving averages, computed from ten years of daily closes,
  keep a one-hour cache.
- Watchlist live quotes and market-wide quotes have separate bulk requests.
  Market quotes persist across watchlist/tab changes. Historical Overview
  baselines refresh daily rather than with every live-price refresh.
- The header's IPO banner comes from `bin/ipos.py`: NYSE listing ceremonies and
  Nasdaq's IPO calendar for the New York date, without SPACs, refreshed hourly while
  the window is open. Logos are NYSE's ceremony images or, for other IPOs, the
  company site's icon via Google; `qml/art/Banner.js` trims and averages them into
  half-size facade cells.
- Market memberships are local snapshots. Index/sector maps use bulk requests;
  they never fan an entire membership into per-symbol charts. Research batches
  have four workers. Market pages stay mounted after the first visit and poll
  only while active.
- `bin/yahoo_http.py` shares anonymous authentication, request pacing and HTTP 429
  backoff across helper processes. Requests ask for gzip, which makes replies a
  quarter of the size and about twice as fast; unpacking is bounded by the same
  4 MB limit. Each request claims a turn 0.25 seconds after the one before and
  waits for it outside the lock, so the chart helper's requests, which take their
  turn at once, never queue behind background requests. Transient network failures and HTTP 500/502/503/504
  responses get two retries after 1 and 2 seconds, respecting shared pacing and
  rate-limit cooldowns on each attempt. When a request's last attempt fails on the
  network or with a server error, `traffic.json` records `outage: {since, failures}`;
  any other reply from Yahoo, even a 404, clears it, and a request held back by the
  cooldown changes nothing. Normal operation writes nothing extra, and there are no
  health-check requests. A banner above the right panel's tabs shows the cooldown
  ("Retrying at HH:MM", which takes precedence) or an outage of at least three
  failures over 15 seconds. Manual refresh bypasses ordinary caches and
  failure cooldowns, while respecting that shared throttle and successful daily
  Overview baselines. `bin/tradingview.py` shares bounded scanner transport and
  share-class symbol mapping.

Network hosts: `query1.finance.yahoo.com`, `finance.yahoo.com`, `fc.yahoo.com`,
`api.nasdaq.com`, `www.nyse.com`, `scanner.tradingview.com`, `economic-calendar.tradingview.com`,
`production.dataviz.cnn.io`, `news.google.com`, `www.google.com`,
`api.stocktwits.com`, and `apewisdom.io`; Google's site icons redirect to
`*.gstatic.com`. Thumbnails use provider-supplied image URLs;
source links open externally. The earnings-release helper resolves Google's
redirect on demand. Yahoo's anonymous cookies and crumb stay in the local state directory.

## Checks

From the repository root:

```sh
python3 -m unittest discover -s tests -v
node tests/test_chart.cjs
node tests/test_treemap.cjs
node tests/test_watchlist_order.cjs
node tests/test_quote_retry.cjs
node tests/test_pixel_art.cjs
node tests/test_market_assets.cjs
node tests/test_banner.cjs
node tests/test_chart_refresh.cjs
node tests/test_research_refresh.cjs
node tests/test_extended_hours.cjs
node tests/test_yahoo_status.cjs
bash -n install install-launcher uninstall
shellcheck install install-launcher uninstall
omarchy plugin validate .
git diff --check
```

Node.js and ShellCheck are development dependencies only. For helper/UI experiments, set
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
loads; keep the cover and gallery consistent with the current branch. Full-window
captures are **1850 × 1400**; gallery thumbnails in `docs/screenshots/thumbs/` are
600 pixels wide and link to the originals. The cover shows AMD in the initial
1D view after loading, with default chart controls and collapsed research sections.

### Text UI inspection

The app exposes text inspection over IPC for checking behavior after a shell
reload:

```sh
C=io.github.dmitry-solomadin.omastocks
omarchy-shell $C open
omarchy-shell $C view market                        # stock, market or watchlist
omarchy-shell $C dump crossAssets                   # visible text under an objectName; no name dumps the window
omarchy-shell $C activate crossAssetsView_global    # click a named button or switch
journalctl --user --since "-2 min" | grep -iE "omastocks.*(warn|error)"
```

`dump` prints one line per visual row. `*` marks bold (selected) text and `[name]`
marks items that `activate` can reach. `no item <name>` means nothing has that
objectName; empty output means it exists but is hidden (another view, a collapsed
section). Dumping the window shows what is currently visible. QML runtime errors,
such as JavaScript Qt's engine lacks (`flatMap`), appear in the journal and can
leave a page blank even when the tests pass.

Interactive elements have an `objectName`. Buttons activate through `clicked()`;
anything else (a `TapHandler`, a clickable label) needs an `activate()` function.
Everything clickable shows a pointing-hand cursor. `ActionButton` provides this
itself; a `MouseArea`, `ItemDelegate` or menu item needs its own `cursorShape`
(or a `HoverHandler` with one), and an inline link switches on `hoveredLink`.

Text inspection covers behavioral checks. Screenshots cover layout, spacing,
color, theming, clipping and elision; `grim` can capture the window at its
`hyprctl clients` geometry.
