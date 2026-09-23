# Watchlist membership snapshots

## Index heatmaps

`index-presets.json` contains one-time TradingView index memberships downloaded
on 2026-09-22: **S&P 500 (503 listings)**, **Nasdaq 100 (101 listings)**, and
**Russell 2000 (1,940 listings)**. Counts are provider listings, including separate
share classes; the Russell snapshot preserves the provider's OTC listings too.

The source was the public TradingView scanner's index constituent symbol sets
`SYML:SP;SPX`, `SYML:NASDAQ;NDX`, and `SYML:TVC;RUT`. Each response was retrieved
with a range of 0–3,000, and its reported `totalCount` matched all returned rows.
Source component-page URLs, retrieval dates, and response hashes are retained.
Company names and exact exchange-qualified `providerSymbol` values are stored;
share-class dots are converted to Yahoo hyphens only in the app's `symbol` field.

At runtime each selected index uses **one bulk TradingView POST** with those saved
identifiers. Membership is not re-downloaded. Daily/YTD returns and market caps
come from that response, with unavailable listings left missing and no per-symbol
fallback requests. Tile area represents company market cap, not official index
weights. These are membership snapshots, not a guarantee of current index coverage
after constituent changes.

## Yahoo sector Top Companies

`yahoo-sector-presets.json` is the smaller snapshot downloaded on 2026-09-22
from <https://finance.yahoo.com/sectors/> and its sector data endpoints. It
contains **11 lists of 50 stocks each (550 distinct tickers)**:

- Technology
- Financial Services
- Consumer Cyclical
- Communication Services
- Healthcare
- Industrials
- Consumer Defensive
- Energy
- Basic Materials
- Real Estate
- Utilities

Each list preserves Yahoo's `data.topCompanies` array and ordering. These are
capped Top Companies lists, **not complete sector memberships**. The website
may initially display fewer rows than the endpoint returns. Each record includes
the full sector's reported company count separately, plus the source URL,
endpoint, retrieval timestamp, and response SHA-256 hash. Provider-omitted names
are stored as `null`; tickers and share classes are preserved as returned.

The download used an anonymous Yahoo cookie/crumb session, without an account or
API key. No cookies or crumbs are stored in this repository. This is a static
membership snapshot, not a scheduled membership download. Market uses these
memberships and matches values from a single bulk sector response for the selected
sector. Missing symbols are left unavailable. Overview and Calendar continue to
use the active personal watchlist, with bulk quote and earnings requests.

Print the Yahoo lists:

```sh
python3 - <<'PY'
import json
from pathlib import Path
from textwrap import fill
snapshot = json.loads(Path('data/yahoo-sector-presets.json').read_text())
for group in snapshot['lists']:
    print(f"\n{group['name']} — {group['count']} entries")
    print(fill(', '.join(row['symbol'] for row in group['members']), width=100))
PY
```

## Stock Analysis full memberships

`watchlist-presets.json` contains a one-time download from Stock Analysis on
2026-09-22. It stores symbols, company names, source URLs, retrieval timestamps,
and source-page SHA-256 hashes. All source pages were downloaded; list counts
were checked against the source headings, with consecutive row numbers and
unique symbols within each list.

| List | Entries | Source |
| --- | ---: | --- |
| Big Tech / Magnificent Seven | 7 | <https://stockanalysis.com/list/magnificent-seven/> |
| Semiconductors | 70 | <https://stockanalysis.com/stocks/industry/semiconductors/> |
| Financials | 1,103 | <https://stockanalysis.com/stocks/sector/financials/> |
| Healthcare | 1,048 | <https://stockanalysis.com/stocks/sector/healthcare/> |
| Energy | 251 | <https://stockanalysis.com/stocks/sector/energy/> |
| Consumer Staples | 242 | <https://stockanalysis.com/stocks/sector/consumer-staples/> |
| Consumer Discretionary | 531 | <https://stockanalysis.com/stocks/sector/consumer-discretionary/> |

There are 3,252 memberships and 3,249 distinct symbols. These are full source
tables, not curated top-20 lists. Membership and ordering reflect the download;
no automatic updates or quotes are stored. The snapshot is ready for future app
integration but is not currently loaded by Overview, Calendar, or personal
watchlists.

The source's classifications are preserved, including foreign companies/ADRs,
multiple share classes, and other instruments in its tables. Big Tech is
explicitly defined here as the Magnificent Seven, including Tesla. Consumer is
split into two sectors, and semiconductor equipment belongs to a separate
industry that is not included in the Semiconductors list.

For US share classes, dots are translated to Yahoo's hyphens (for example,
`BRK.B` → `BRK-B`); `sourceSymbol` preserves the original spelling. Individual
symbols have not been checked for quote or earnings-provider coverage.

Print every downloaded ticker:

```sh
python3 - <<'PY'
import json
from pathlib import Path
from textwrap import fill
snapshot = json.loads(Path('data/watchlist-presets.json').read_text())
for group in snapshot['lists']:
    print(f"\n{group['name']} — {group['count']} entries")
    print(fill(', '.join(row['symbol'] for row in group['members']), width=100))
PY
```
