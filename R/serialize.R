# Serialisation (REVIEW s6.5): an edit is a list of structured operations, not an
# opaque grob. An agent can write them out, audit them, and re-apply them to a
# freshly built figure so the drawing code and the visual polish stay separate.

#' The scene's edits as a plain manifest (list of operations)
#' @param scene An `inc_scene` or `inc_svg`.
#' @export
as_manifest = function(scene) {
  if (inherits(scene, "inc_svg")) {
    return(list(
      incantation_version = 2L,
      kind = "svg",
      source_hash = scene$source_hash,
      device = list(width = scene$width, height = scene$height, units = "pt"),
      operations = scene$operations
    ))
  }
  list(
    incantation_version = 2L,
    kind = "scene",
    device = scene$device,
    operations = lapply(scene$transforms, function(tr) {
      tr[!vapply(tr, is.null, logical(1))]
    })
  )
}

#' Write / read an edit manifest as JSON
#' @param scene An `inc_scene` or `inc_svg`.
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
#' @param scene An `inc_scene` or `inc_svg`. @param path File path of a manifest.
#' @rdname incantation-io
#' @export
apply_incantation = function(scene, path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    inc_abort("apply_incantation() needs the 'jsonlite' package.", class = "inc_error_missing_pkg")
  }
  man = jsonlite::read_json(path, simplifyVector = FALSE)
  if (!identical(as.integer(man$incantation_version), 2L)) {
    inc_abort("unsupported incantation manifest; expected version 2.",
              class = "inc_error_manifest_version")
  }
  if (inherits(scene, "inc_svg")) return(.apply_svg_incantation(scene, man))
  if (!is.null(man$kind) && !identical(man$kind, "scene")) {
    inc_abort("an SVG manifest cannot be applied to an inc_scene.", class = "inc_error_manifest_kind")
  }
  ops = .manifest_ops(man$operations)
  bound = Filter(function(op) {
    type = .scalar_value(op$type)
    identical(type, "translate") ||
      (identical(type, "decorate_group") &&
       identical(.scalar_value(op$span$type), "absolute"))
  }, ops)
  if (length(bound) && !.same_device(scene$device, man$device)) {
    err_device_mismatch(man$device, scene$device)
  }
  for (op in ops) {
    op$type = .scalar_value(op$type)
    if (identical(op$type, "decorate_group")) {
      scene = .add_decoration(scene, op, activate = FALSE)
      next
    }
    .validate_manifest_op(scene, op)
    scene$transforms = c(scene$transforms, list(op))
  }
  scene
}

.manifest_ops = function(x) {
  if (is.null(x) || length(x) == 0) return(list())
  if (is.data.frame(x)) return(lapply(seq_len(nrow(x)), function(i) as.list(x[i, ])))
  if (!is.list(x[[1]])) return(list(as.list(x)))
  x
}

.same_device = function(a, b) {
  isTRUE(all.equal(.to_pt(a$width, a$units), .to_pt(b$width, b$units))) &&
    isTRUE(all.equal(.to_pt(a$height, a$units), .to_pt(b$height, b$units)))
}

.validate_manifest_target = function(scene, id) {
  el = scene$registry[[id]]
  if (is.null(el)) err_no_match(sprintf("manifest target `%s`", id), names(scene$registry))
  if (isTRUE(el$is_empty)) err_empty_target(id)
}

.validate_manifest_op = function(scene, op) {
  allowed = c("translate", "z", .constraint_types, "decorate_group")
  if (is.null(op$type) || !op$type %in% allowed) {
    inc_abort(sprintf("unsupported manifest operation `%s`.", op$type %||% "<missing>"),
              class = "inc_error_manifest_operation")
  }
  if (identical(op$type, "decorate_group")) {
    .validate_decoration_op(scene, op)
    return(invisible(op))
  }
  .validate_manifest_target(scene, .scalar_value(op$target))
  op$target = .scalar_value(op$target)
  if (op$type %in% .constraint_types) .validate_manifest_target(scene, op$reference)
  invisible(op)
}

.apply_svg_incantation = function(x, man) {
  if (!identical(man$kind, "svg")) {
    inc_abort("a scene manifest cannot be applied to an inc_svg.", class = "inc_error_manifest_kind")
  }
  if (!identical(man$source_hash, x$source_hash)) {
    inc_abort("SVG manifest source hash does not match this snapshot.", class = "inc_error_svg_source")
  }
  base = x
  base$operations = list()
  available = svg_manifest(base)$id
  ops = .manifest_ops(man$operations)
  allowed = c("translate", "scale", "rotate", "style", "z")
  for (op in ops) {
    if (is.null(op$type) || !op$type %in% allowed) {
      inc_abort(sprintf("unsupported SVG manifest operation `%s`.", op$type %||% "<missing>"),
                class = "inc_error_manifest_operation")
    }
    targets = unlist(op$targets, use.names = FALSE)
    missing = setdiff(targets, available)
    if (length(missing)) err_no_match(sprintf("SVG manifest target `%s`", missing[[1]]), available)
    op$targets = targets
    x$operations = c(x$operations, list(op))
  }
  x
}
