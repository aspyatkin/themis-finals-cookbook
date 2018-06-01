function flag_custom (req, res, code, msg) {
  res.status = code
  res.contentType = 'text/plain; charset=utf-8'
  res.contentLength = msg.length
  res.sendHeader()
  res.send(msg)
  res.finish()
}

function flag_getinfo_403 (req, res) {
  flag_custom(req, res, 403, 'ERROR_ACCESS_DENIED')
}

function flag_getinfo_404 (req, res) {
  flag_custom(req, res, 404, 'ERROR_NOT_FOUND')
}

function flag_getinfo_429 (req, res) {
  flag_custom(req, res, 429, 'ERROR_RATELIMIT')
}

function flag_submit_403 (req, res) {
  flag_custom(req, res, 403, 'ERROR_ACCESS_DENIED')
}

function flag_submit_413 (req, res) {
  flag_custom(req, res, 413, 'ERROR_FLAG_INVALID')
}

function flag_submit_429 (req, res) {
  flag_custom(req, res, 429, 'ERROR_RATELIMIT')
}
