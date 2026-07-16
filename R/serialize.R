# Serialisation (REVIEW s6.5): an edit is a list of structured operations, not an
# opaque grob. An agent can write them out, audit them, and re-apply them to a
# freshly built figure so the drawing code and the visual polish stay separate.

#' The scene's edits as a plain manifest (list of operations)
#' @param scene An `inc_scene`.
#' @export
as_manifest = function(scene) {
  list(
    incantation_version = 1L,
    device = scene$device,
    operations = lapply(scene$transforms, function(tr) {
      tr[!vapply(tr, is.null, logical(1))]
    })
  )
}

#' Write / read an edit manifest as JSON
#' @param scene An `inc_scene`.
#' @param path File path.
#' @name incantation-io
#' @export
write_incantation = function(scene, path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    inc_abort("write_incantation() needs the 'jsonlite' package.", class = "inc_error_missing_pkg")
  }
  jsonlite::write_json(as_manifest(scene), path, auto_unbox = TRUE, pretty = TRUE)
  invisible(path)
}

#' Re-apply a manifest's operations to a scene
#' @param scene An `inc_scene`. @param path File path of a manifest.
#' @rdname incantation-io
#' @export
apply_incantation = function(scene, path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    inc_abort("apply_incantation() needs the 'jsonlite' package.", class = "inc_error_missing_pkg")
  }
  man = jsonlite::read_json(path, simplifyVector = TRUE)
  ops = man$operations
  for (i in seq_len(nrow_or_len(ops))) {
    op = if (is.data.frame(ops)) as.list(ops[i, ]) else ops[[i]]
    scene$transforms = c(scene$transforms, list(op))
  }
  scene
}

nrow_or_len = function(x) if (is.data.frame(x)) nrow(x) else length(x)
