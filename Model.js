var FILE_TYPES = {
  // Office and Google Workspace exports.
  doc: "word", docx: "word", odt: "word", rtf: "word", pages: "word",
  xls: "sheet", xlsx: "sheet", ods: "sheet", csv: "sheet", tsv: "sheet", numbers: "sheet",
  ppt: "slides", pptx: "slides", odp: "slides", key: "slides",
  pdf: "pdf",

  // Media.
  jpg: "image", jpeg: "image", png: "image", gif: "image", webp: "image",
  avif: "image", heic: "image", svg: "image", bmp: "image", tif: "image", tiff: "image",
  mp4: "video", mov: "video", mkv: "video", webm: "video", avi: "video",
  m4v: "video", mpg: "video", mpeg: "video", wmv: "video",
  mp3: "audio", m4a: "audio", wav: "audio", flac: "audio", ogg: "audio", opus: "audio", aac: "audio",

  // Text, source, data, and archives.
  txt: "text", md: "text", markdown: "text", log: "text",
  js: "code", jsx: "code", ts: "code", tsx: "code", py: "code", rb: "code",
  go: "code", rs: "code", java: "code", c: "code", h: "code", cpp: "code",
  css: "code", scss: "code", html: "code", htm: "code", sh: "code", sql: "code",
  json: "data", jsonc: "data", yaml: "data", yml: "data", toml: "data", xml: "data",
  zip: "archive", rar: "archive", "7z": "archive", tar: "archive", gz: "archive",
  bz2: "archive", xz: "archive", tgz: "archive"
}

var FILE_GLYPHS = {
  word: "󰈬",
  sheet: "󰈛",
  slides: "󰈧",
  pdf: "󰈦",
  image: "󰈟",
  video: "󰈫",
  audio: "󰈣",
  text: "󰈙",
  code: "󰅩",
  data: "󰘦",
  archive: "󰀼",
  file: "󰈔"
}

function defaultStatus() {
  return {
    ok: true,
    installed: false,
    running: false,
    authenticated: false,
    statusText: "Unavailable",
    accountPath: "",
    remoteName: "",
    usedBytes: 0,
    quotaBytes: 0,
    usagePercent: 0,
    quotaKnown: false,
    files: [],
    warning: "",
    lastError: ""
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    parsed.files = Array.isArray(parsed.files) ? parsed.files : []
    return parsed
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Failed to parse Google Drive status"
    return failed
  }
}

function parseSearch(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, files: [], truncated: false, lastError: "Empty search response" }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object")
      return { ok: false, files: [], truncated: false, lastError: "Invalid search response" }
    parsed.files = Array.isArray(parsed.files) ? parsed.files : []
    parsed.truncated = parsed.truncated === true
    return parsed
  } catch (e) {
    return { ok: false, files: [], truncated: false, lastError: "Failed to parse Google Drive search" }
  }
}

function fileExtension(name) {
  var value = String(name || "").toLowerCase()
  var index = value.lastIndexOf(".")
  return index >= 0 ? value.substring(index + 1) : ""
}

function fileKind(name) {
  var ext = fileExtension(name)
  if (FILE_TYPES[ext]) return FILE_TYPES[ext]

  // Google Drive recordings can be exposed without a filename extension.
  var value = String(name || "").toLowerCase()
  if (/(^|[ _-])(recording|video)([ _-]|$)/.test(value)) return "video"
  return "file"
}

function fileGlyph(name) {
  return FILE_GLYPHS[fileKind(name)] || FILE_GLYPHS.file
}

function formatBytes(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = value >= 100 || index === 0 ? 0 : (value >= 10 ? 1 : 2)
  return value.toFixed(decimals).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1") + " " + units[index]
}

function formatPercent(value) {
  var number = Number(value || 0)
  if (!isFinite(number) || number <= 0) return "0%"
  if (number >= 10) return Math.round(number) + "%"
  return number.toFixed(1).replace(/\.0$/, "") + "%"
}

function usageText(usedBytes, quotaBytes, quotaKnown) {
  if (quotaKnown && Number(quotaBytes || 0) > 0)
    return formatBytes(usedBytes) + " of " + formatBytes(quotaBytes)
  return formatBytes(usedBytes)
}

function relativeTime(timestampSec, nowMs) {
  var ts = Number(timestampSec || 0)
  if (!isFinite(ts) || ts <= 0) return "Unknown time"
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = Math.max(0, Math.floor((now - ts * 1000) / 1000))
  if (diff < 60) return "Just now"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(days / 365) + "y ago"
}

function fileMeta(file, nowMs) {
  if (!file) return ""
  var parts = [relativeTime(file.modifiedTs, nowMs)]
  var folder = String(file.folder || "")
  if (folder !== "") parts.push(folder)
  return parts.join(" · ")
}

function shortHomePath(path, home) {
  var value = String(path || "")
  var prefix = String(home || "")
  if (prefix !== "" && value === prefix) return "~"
  if (prefix !== "" && value.indexOf(prefix + "/") === 0) return "~" + value.substring(prefix.length)
  return value
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    parseSearch: parseSearch,
    defaultStatus: defaultStatus,
    fileExtension: fileExtension,
    fileKind: fileKind,
    fileGlyph: fileGlyph,
    formatBytes: formatBytes,
    formatPercent: formatPercent,
    usageText: usageText,
    relativeTime: relativeTime,
    fileMeta: fileMeta,
    shortHomePath: shortHomePath
  }
}
