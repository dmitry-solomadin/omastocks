"""Named watchlist persistence; legacy entries remain an active-list mirror."""

import uuid


def normalize(state):
    if "watchlists" not in state:
        state["watchlists"] = [{"id": "default", "name": "Watchlist", "entries": state["entries"]}]
        state["activeWatchlist"] = "default"
    lists = state["watchlists"]
    if (not isinstance(lists, list) or not lists or len(lists) > 12
            or any(not isinstance(row, dict) or not isinstance(row.get("entries"), list)
                   or not isinstance(row.get("id"), str) or not row["id"]
                   or not isinstance(row.get("name"), str) or not row["name"].strip() for row in lists)
            or len({row["id"] for row in lists}) != len(lists)):
        raise ValueError("Invalid watchlists. File left untouched.")
    active = next((row for row in lists if row["id"] == state.get("activeWatchlist")), None)
    if active is None:
        raise ValueError("Invalid active watchlist. File left untouched.")
    for row in lists:
        entries = row["entries"]
        if (len(entries) > 60 or any(not isinstance(entry, dict) or not isinstance(entry.get("symbol"), str)
                                    or not entry["symbol"] for entry in entries)
                or len({entry["symbol"] for entry in entries}) != len(entries)):
            raise ValueError("Invalid watchlist entries. File left untouched.")
    state["entries"] = active["entries"]


def selected(state, identity=""):
    row = next((row for row in state["watchlists"] if row["id"] == (identity or state["activeWatchlist"])), None)
    if row is None:
        raise ValueError("That watchlist no longer exists. Refresh and try again.")
    return row


def change(state, action, identity="", name=""):
    if action in ("create", "rename"):
        name = name.strip()
        if not name or len(name) > 40 or any(ord(c) < 32 for c in name):
            raise ValueError("Use a watchlist name of 1–40 characters.")
        if any(row["name"].casefold() == name.casefold() and (action == "create" or row["id"] != identity)
               for row in state["watchlists"]):
            raise ValueError("A watchlist with that name already exists.")
    if action == "create":
        if len(state["watchlists"]) >= 12:
            raise ValueError("You can create up to 12 watchlists.")
        identity = uuid.uuid4().hex
        state["watchlists"].append({"id": identity, "name": name, "entries": []})
        state["activeWatchlist"] = identity
    elif action == "rename":
        selected(state, identity)["name"] = name
    elif action == "select":
        state["activeWatchlist"] = selected(state, identity)["id"]
    elif action == "remove":
        selected(state, identity)
        if len(state["watchlists"]) == 1:
            raise ValueError("Keep at least one watchlist.")
        state["watchlists"] = [row for row in state["watchlists"] if row["id"] != identity]
        if state["activeWatchlist"] == identity:
            state["activeWatchlist"] = state["watchlists"][0]["id"]
    else:
        raise ValueError("Unknown watchlist action.")
    normalize(state)


def all_entries(state):
    rows = {}
    for watchlist in state["watchlists"]:
        for entry in watchlist["entries"]:
            ticker = entry["symbol"]
            if ticker not in rows or entry.get("favorite"):
                rows[ticker] = entry
    return list(rows.values())
