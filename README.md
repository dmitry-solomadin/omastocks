# Omastocks

A window-first stock watchlist for Omarchy, with an optional favorites strip.

Six chart ranges, five-stock comparisons, moving averages, earnings and news,
plus quarterly/annual financial statements and valuation ratios. No API keys.

Built with Quickshell and Omarchy's live theme tokens. The main view is a regular
Wayland window: tile it, move it to a workspace, or put it in the scratchpad.
The window and its heading are named **Stocks**; the plugin and launcher are **Omastocks**.

![Omastocks watchlist and stock chart](preview.png)

## Install

Requires **Omarchy Quattro's Quickshell-based shell**, Python **3.10+**, and the
system timezone database (`tzdata`). Uses Omarchy's `qs.Commons` / `qs.Ui` and
Quickshell's Qt Quick Controls, layouts, IO and Wayland modules. Bash, Git, and
the standard coreutils utilities are used for installation. These are provided
by a current Omarchy installation; no Python packages or API keys are required.

```sh
omarchy plugin add https://github.com/dmitry-solomadin/omastocks --enable
omarchy-shell io.github.dmitry-solomadin.omastocks open
```

Click the favorites strip to open **Omastocks**. To also add it to your application
launcher, run the optional, user-local launcher installer:

```sh
~/.config/omarchy/plugins/io.github.dmitry-solomadin.omastocks/install-launcher
```

No root access or changes to `/usr/share/omarchy` are needed. The marketplace's
installer loads the manifest directly; it does not run this repository's scripts.

Closing the window leaves the strip running. Use the gear button to open
**Settings**, then toggle **Show favorites in bar**. You can also hide it with
`omarchy bar set io.github.dmitry-solomadin.omastocks showStrip false --json`. The window remains
available from the launcher. Set it to `true` to show the strip again.

The bar defaults to **ticker + daily percentage change**. In Settings, choose
any combination of **Price**, **Percentage change**, and **Price change ($)**,
and adjust **Maximum width**. Absolute changes use each stock's quote currency.
These preferences also appear in Omarchy's bar widget settings (`showPrice`,
`showPercent`, `showChange`, and `maxWidth`).

When the favorites fit, the strip is stationary and only takes the space it
needs. Otherwise, all favorites scroll continuously right-to-left; hover to pause.
The threshold is measured using the bar's actual font: the sum of each entry's
rendered width, plus an 18-unit gap between entries and 8.5-unit padding on each
side, compared with the available width (capped at `maxWidth`, default 360).
Spacing and the width cap follow Omarchy's UI scale. Text is remeasured when
quotes, favorites, selected fields, or fonts change. Vertical bars use the Omastocks
icon. The favorites widget has no hover tooltip.

### Update and remove

```sh
omarchy plugin update io.github.dmitry-solomadin.omastocks
# Remove the plugin and optional launcher, after Omarchy asks for confirmation:
~/.config/omarchy/plugins/io.github.dmitry-solomadin.omastocks/uninstall
```

Removal preserves your watchlist and cached data. If you did not install the
launcher, `omarchy plugin remove io.github.dmitry-solomadin.omastocks` also works.
The scripts accept `--yes` for explicitly confirmed, non-interactive removal.

## Use

- Click a watchlist entry, or use Up/Down, to immediately view its chart and market statistics.
- Drag a watchlist row up or down to reorder it. The insertion line marks the
  drop position; hold near the top or bottom to scroll longer lists. The order is
  saved and also determines the order of starred stocks in the bar. Clear search
  before rearranging; Escape or dropping outside the list cancels a drag.
- Type in the sidebar to filter your watchlist and automatically search Yahoo Finance.
- Click **+** beside a search result to add it directly to your watchlist, or
  click the result to preview it first.
- Star a stock to show it in the bar. Removing it from the watchlist also removes
  its star. **Undo** beside the watchlist controls restores an accidentally removed entry.
- Choose 1D, 1W, 1M, 3M, 1Y or 5Y; hover the chart to inspect a price.
- Market Details uses equal-width columns. Its 52-week range gauge shows the low
  and high at either end, with a dot for the current price; hover for exact values.
- Click and drag across the chart to compare two points. The highlighted interval
  shows the price and percentage change from its earlier point to its later one,
  in either drag direction. Endpoints snap to available quotes. Click again or
  press Escape to clear it; loading new chart data also clears the selection.
- The period's percentage change appears just below the range buttons. A dragged
  selection replaces it with the selected interval's price and percentage change.
- During an open market session, 1D spans through the scheduled market close,
  leaving the remaining time empty. Hours come from the exchange session supplied
  by Yahoo, including early closes; no prices are projected into that space.
- A timestamped **Pre-market / After-hours** quote appears beneath the selected
  stock's daily change when Yahoo supplies an extended-session observation.
  Its change is measured against the preceding regular-session close; the main
  quote, watchlist and favorites ticker use regular-session prices.
- On **1D**, toggle **Extended** to include pre-market and after-hours prices.
  Shaded regions identify extended sessions and hover labels identify the session.
  Session boundaries come from Yahoo's exchange timestamps, including early
  closes and daylight saving changes. Unsupported symbols disable the toggle.
  The choice is remembered for the shell session and returns after leaving
  Compare or switching back from a longer range.
- Extended prices are sampled from Yahoo's five-minute chart feed and may be
  delayed. Their date/time is always shown in your local timezone, including for
  a completed session. The selected stock's extended feed refreshes once a minute
  while the window is open, independently of regular quotes.
- Ctrl+K focuses search; Escape clears it; Ctrl+R refreshes prices.
- Down from the search field selects the first result; Up/Down immediately select adjacent stocks.
- Ctrl+W closes the window.
- Mouse-wheel scrolling moves 96 scaled UI pixels per notch in both panes;
  high-resolution touchpad pixel deltas retain their native movement.

## Chart analysis and company news

- **Settings → Chart → Volume bars** shows per-interval trading volume below the price chart. Hover a
  regular-session price point to see its volume. Pre-market and after-hours hover
  readouts omit volume. Missing volume is left blank rather than invented.
- **20D MA / 50D MA / 200D MA** toggle daily simple moving averages, using up to
  ten years of daily price history for warm-up. Colors match the buttons. They are
  available on **1M and longer** ranges, and sample daily averages at their chart
  intervals. Intraday ranges omit these overlays to preserve the price scale;
  your selected averages return when switching back to a longer range. The price
  axis includes enabled averages so they remain visible; a distant long-term
  average can make short-term price movement appear flatter. Newly listed stocks
  may not have enough history for every average.
- Click **Compare** next to the MA buttons to replace them with a ticker field.
  Enter a symbol such as **MSFT**, **SPY**, or **^GSPC** and press Enter or **Add**.
  Compare up to **five stocks total**: the selected stock plus four additional
  symbols. Each has an independent request and a distinct, solid-colored line.
  The chart legend identifies each stock and its period return; its **×** removes
  that stock. Failed/loading requests are indicated in the legend, with details
  in its tooltip. All plotted lines use percentage change from their first shared
  trading interval, matching timestamps or session dates rather than sample numbers.
  Hover shows each plotted stock's actual price and currency for a single shared
  date. Missing intervals are skipped rather than filled with invented prices.
  Prices retain each stock's quoted currency; no currency conversion is applied.
  Hover dates omit the time for 1M and longer ranges.
  Moving averages, volume and event markers are hidden in Compare mode. Use the
  **×** beside Add, or Escape, to exit and restore the regular chart and remembered
  MA selections. Click-and-drag interval selection remains available in regular mode.
- **Settings → Chart → Event markers** marks recent reported earnings (**E**), ex-dividend dates (**D**), and
  splits (**S**). Hover for details. A **+** combines events in the same chart bar.
  Only events within the visible date range are plotted.
- The **Earnings** section shows the next estimated report date and the latest
  reported EPS versus its estimate, plus reported revenue and its consensus
  estimate for the same release. Revenue uses TradingView's public scanner feed,
  includes its currency, and is attached only when the release date matches the
  earnings report. Unavailable revenue or estimates display as **—**.
  Nasdaq/Zacks provides upcoming estimates and
  a limited recent earnings history for supported US stocks. Dates are labeled
  estimated; unsupported symbols and provider failures show an unavailable state.
- **Latest News** shows relevant company headlines, publishers, dates and optional
  thumbnails from Yahoo. Clicking a story opens the publisher in your browser.
  No API key is required. This is a headline feed, not a full-article reader.

## Financial statements and valuations

Expand **Financials** below Market Details. Choose **Income**, **Balance Sheet**,
or **Cash Flow**, then **Quarterly** or **Annual**. Click any metric row to chart
its history. Scroll the table horizontally in narrow windows.
Vertical wheel scrolling over the table continues scrolling the company pane.

- Income: revenue, cost of revenue, gross profit, R&D, selling/administration,
  operating income, EBITDA, net income and diluted EPS.
- Balance sheet: cash, cash/short-term investments, assets, liabilities, debt,
  net debt and shareholders' equity.
- Cash flow: operating, investing and financing cash flow, capex, free cash
  flow, share repurchases and dividends paid.
- Derived metrics: gross/operating/net margins, revenue growth versus the same
  period a year earlier, current ratio, debt/equity and free cash flow margin.
  Ratios require matching dates/currencies and positive denominators.
- Market Details adds TradingView market cap, trailing P/E, price/sales,
  price/book, EV/EBITDA, sector and industry for supported US listings.
- **Filings ↗** opens the symbol's SEC EDGAR company page in your browser.
- **Yahoo ↗** opens the selected Income, Balance Sheet, or Cash Flow statement on
  Yahoo Finance for more detail.

Yahoo's fundamentals-timeseries endpoint supplies the statements. It currently
usually returns **four annual and five quarterly periods**, with coverage varying
by metric and company. Entirely unavailable metrics are omitted; missing cells
are **—**, never zero. Indices/ETFs may have no statements. Some international
companies lack quarterly cash flow. Each value retains the **statement reporting
currency**, which can differ from the stock's trading currency. Money is shown
in units, millions (M), billions (B), or trillions (T); EPS stays per share.

Period-end dates are displayed as Yahoo supplies them; these may be normalized
to calendar month-end rather than the company's exact fiscal closing date.
Only standalone three-month or full-year records are accepted, not YTD figures.
Statement diluted EPS is separate from the earnings-surprise feed's EPS and
can differ in definition. Valuations retain TradingView's field definitions and
are not currency-converted. Financials are fetched only when expanded and cached
for one day; valuations cache for one hour. The refresh/info controls expose
source and error details; saved results remain available after a failed refresh.

## Analyst recommendations

Expand **Analysts** below Financials. Use **TipRanks ↗** in its header to open the
stock's full analyst forecasts and price targets. The section shows:

- A green/neutral/red **Buy / Hold / Sell** distribution with counts and the total
  number of analysts. Hover a segment for its percentage.
- **Average price target** and its implied upside/downside versus the current
  regular-session quote.
- A **target-price gauge**: the highlighted range runs from low to high, the
  accent tick marks the average target, and the dot marks the current price.
  The scale expands when the current price falls outside the target range.
- Expand **History** for monthly average targets and recommendation counts,
  newest first. Coverage currently typically includes 13 monthly snapshots.

Counts, targets, and history come together from Nasdaq's public `targetprice`
endpoint (TipRanks). They are not mixed with Nasdaq's separate ratings feed,
which can use a different analyst group. Historical snapshots retain their own
counts, so the latest month's counts may differ from the current summary.
Targets are USD amounts for supported US listings. Implied returns and the
current-price marker appear only when the quote currency matches. Missing counts
stay missing; a distribution requires all three counts and a positive total.

Analyst data loads on demand and caches for one day. The refresh button's tooltip
shows the source, retrieval time and any error; failed refreshes retain saved
results. Retrieval time is not the publication date of an individual rating.

News, earnings, financials, analysts, valuations, extended hours, moving averages and comparisons use independent helper processes
and per-request caches under the state's `research/` directory. They do not take
the watchlist lock or wait behind the price/chart queue. News caches for ten minutes,
earnings for six hours, daily-average history for one hour, and comparison charts
for one minute intraday or one hour historically. Failed refreshes retain saved
data and back off before retrying. Each section has its own loading/error state;
Ctrl+R also refreshes these sections. Volume and event visibility are saved in
plugin settings. Moving-average and comparison choices last for the shell session.

## Data

Yahoo Finance's unofficial chart, search and fundamentals endpoints supply prices,
history, corporate actions, headlines and financial statements; Nasdaq/Zacks
supplies earnings dates and EPS; TradingView supplies valuations and earnings
revenue comparisons. Prices may be delayed. Quote currency is shown in the
window; chart hover times use your computer's local timezone. Requests are
cached, and failed refreshes keep the last successful data marked as stale.
The bar polls every five minutes. Opening the window refreshes data older than
one minute. Search waits for a 300 ms pause in typing before requesting results;
replies for older queries are ignored.

The initial watchlist is AAPL, MSFT, NVDA, GOOGL and AMZN; AAPL and NVDA are
starred. State lives in `${XDG_STATE_HOME:-~/.local/state}/omarchy/io.github.dmitry-solomadin.omastocks`.
Watchlist edits are atomic and protected by a file lock. The Python helpers handle
market requests and watchlist storage. Bar preferences are saved through Omarchy's
plugin settings API, preserving the other settings in `shell.json`.

### Network and storage

The helpers contact `query1.finance.yahoo.com`, `api.nasdaq.com` and
`scanner.tradingview.com` over HTTPS. The current ticker/search query is sent to
the corresponding provider; watchlist files stay local. News thumbnails load
from image URLs supplied by Yahoo. News, earnings searches and filing links open
in your default browser. No telemetry, credentials or paid services are used.
These are public, unofficial endpoints and may change or be rate-limited.
The MIT license covers the code; external market data and publisher images
remain subject to their respective providers' terms.

## Development

For a development checkout:

```sh
git clone https://github.com/dmitry-solomadin/omastocks
cd omastocks
./install
```

`install` validates and symlinks this directory into the user plugin directory,
installs the launcher, then enables the plugin. It refuses to replace a different
existing installation. Update this checkout with `git pull`. After editing
QML, run `omarchy restart shell` to reload the shared store and clear cached QML
types. No files under `/usr/share/omarchy` are modified.

```sh
python3 -m unittest discover -s tests -v
node tests/test_chart.cjs
omarchy plugin validate .
python3 bin/stocks.py snapshot
python3 bin/stocks.py chart AAPL 1M
omarchy-shell io.github.dmitry-solomadin.omastocks status
```

Node.js is needed only for the chart-math tests. For isolated helper runs, set
`STOCKS_STATE_DIR` to a test directory; never copy test state over your live data.

For the window lifecycle check, open Omastocks, close it with Hyprland's Super+W,
then reopen it from the launcher. Repeat with Ctrl+W. A compositor close and
an in-app close take different paths; both must allow the window to reopen.

Assumes a running Omarchy shell with `qs.Commons` and `qs.Ui`, Quickshell's
`FloatingWindow`, and Yahoo's current public chart/search response shapes.
The UI uses Omarchy's font, spacing, rounding, foreground, background and accent;
gains and losses consistently use green/red, independent of the theme palette.

Inspired by the favorites-strip interaction in CostaFot's Markets plugin.
This is a separate implementation focused on stocks and a workspace window.

## License

[MIT](LICENSE). Plugin ID: `io.github.dmitry-solomadin.omastocks`.
