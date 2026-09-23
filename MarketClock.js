// US equity session clock in Eastern Time. Holidays are not modelled: the
// provider's marketState decides the session, this only positions and counts down.
var preOpen = 240, regularOpen = 570, regularClose = 960, postClose = 1200

function firstSunday(year, month) {
    return 1 + (7 - new Date(Date.UTC(year, month, 1)).getUTCDay()) % 7
}

// DST runs from the second Sunday of March 02:00 EST to the first Sunday of
// November 02:00 EDT.
function offsetHours(utcMs) {
    const year = new Date(utcMs).getUTCFullYear()
    const start = Date.UTC(year, 2, firstSunday(year, 2) + 7, 7)
    const end = Date.UTC(year, 10, firstSunday(year, 10), 6)
    return utcMs >= start && utcMs < end ? -4 : -5
}

function eastern(utcMs) {
    const local = new Date(utcMs + offsetHours(utcMs) * 3600000)
    return {day: local.getUTCDay(), minutes: local.getUTCHours() * 60 + local.getUTCMinutes() + local.getUTCSeconds() / 60}
}

function weekday(day) { return day >= 1 && day <= 5 }

// Session implied by the clock alone.
function scheduled(utcMs) {
    const now = eastern(utcMs)
    if (!weekday(now.day) || now.minutes < preOpen || now.minutes >= postClose) return "CLOSED"
    if (now.minutes < regularOpen) return "PRE"
    if (now.minutes < regularClose) return "REGULAR"
    return "POST"
}

// Provider marketState reduced to PRE, REGULAR, POST or CLOSED ("" if unknown).
function normalize(raw) {
    if (raw === "REGULAR" || raw === "CLOSED") return raw
    if (raw === "PRE" || raw === "PREPRE") return "PRE"
    if (raw === "POST" || raw === "POSTPOST") return "POST"
    return ""
}

// Resolve a future Eastern wall time using that date's offset, not today's.
// A weekend may contain a DST transition.
function nextEvent(utcMs, boundaries) {
    const offset = offsetHours(utcMs), local = new Date(utcMs + offset * 3600000)
    for (let ahead = 0; ahead < 8; ahead++) {
        const midnight = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() + ahead)
        const day = new Date(midnight).getUTCDay()
        if (!weekday(day)) continue
        for (const minute of boundaries) {
            const wall = midnight + minute * 60000
            const time = wall - offsetHours(wall - offset * 3600000) * 3600000
            if (time > utcMs) return {time: time, minutes: (time - utcMs) / 60000, day: day}
        }
    }
}

// Milliseconds until the next weekday session change.
function nextBoundary(utcMs) {
    return nextEvent(utcMs, [preOpen, regularOpen, regularClose, postClose]).time - utcMs
}

function nextOpen(utcMs) { return nextEvent(utcMs, [regularOpen]) }

// Position through the 04:00–20:00 ET extended day: 1 once a weekday's
// sessions are over, -1 before they start and at weekends.
function position(utcMs) {
    const now = eastern(utcMs)
    if (!weekday(now.day) || now.minutes < preOpen) return -1
    return Math.min(1, (now.minutes - preOpen) / (postClose - preOpen))
}

function duration(minutes) {
    const total = Math.max(1, Math.ceil(minutes))
    const days = Math.floor(total / 1440), hours = Math.floor(total % 1440 / 60), rest = total % 60
    if (days) return days + "d " + hours + "h"
    return hours ? hours + "h " + (rest < 10 ? "0" : "") + rest + "m" : rest + "m"
}

var dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

// Countdown text for a provider-reported state; empty when the clock disagrees
// (for example a holiday), so we never count toward a guessed event.
function countdown(state, utcMs) {
    if (state !== scheduled(utcMs)) return ""
    const now = eastern(utcMs)
    if (state === "REGULAR") return "closes in " + duration(regularClose - now.minutes)
    if (state === "PRE") return "opens in " + duration(regularOpen - now.minutes)
    const next = nextOpen(utcMs)
    return next.minutes < 1440 ? "opens in " + duration(next.minutes) : "opens " + dayNames[next.day] + " 9:30 ET"
}
