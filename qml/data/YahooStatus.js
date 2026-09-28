// One banner for Yahoo Finance trouble, from the helpers' shared traffic.json:
// its rate-limit cooldown, or an outage recorded by the app's own requests.
// The message changes only with the state, never every second.
function status(traffic, now) {
    traffic = traffic && typeof traffic === "object" ? traffic : {}
    if (Number.isFinite(traffic.retryAfter) && traffic.retryAfter > now)
        return {kind: "rate-limited", message: "Yahoo Finance is limiting requests. Retrying at " + clock(traffic.retryAfter) + "."}
    // Several failures over a quarter of a minute, so one failed request never flashes it.
    const outage = traffic.outage || {}
    if (outage.failures >= 3 && Number.isFinite(outage.since) && now - outage.since >= 15)
        return {kind: "unreachable", message: "Can't reach Yahoo Finance. Retrying automatically."}
    return {kind: "", message: ""}
}

// Local HH:MM, rounded up so the retry is never before the time shown.
function clock(seconds) {
    const date = new Date(Math.ceil(seconds / 60) * 60000)
    return ("0" + date.getHours()).slice(-2) + ":" + ("0" + date.getMinutes()).slice(-2)
}
