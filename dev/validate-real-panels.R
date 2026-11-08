# Integration exercise for the saved UC Figure 6 A/C native panel bundle.
# Run with a bundle path and an output directory. Never overwrites research art.
args = commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2)
source_path = Sys.getenv("INCANTATION_SOURCE")
if (nzchar(source_path)) {
  pkgload::load_all(source_path, quiet = TRUE)
} else {
  library(incantation)
}
bundle = normalizePath(args[1])
out = args[2]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
original_hash = unname(tools::md5sum(bundle))
plots = readRDS(bundle)
record = withCallingHandlers({
  a = incantation::incant(plots$A, width = 44, height = 35.6, units = "mm",
                          family = "Arial", plot_ids = "A_sources")
  ids = c("C_TAURUS_expression", "C_TAURUS_rho", "C_Melon_expression",
          "C_Melon_rho", "C_colour_keys", "C_glyph_key")
  c0 = incantation::incant(plots$C, width = 96, height = 53.6, units = "mm",
                           family = "Arial", plot_ids = ids)
  c1 = c0 |> incantation::select_plot(1) |> incantation::translate(dx = .7, unit = "mm")
  manifest = file.path(out, "C_micro_edit.json")
  incantation::write_incantation(c1, manifest)
  replay = incantation::apply_incantation(c0, manifest)
  stopifnot(isTRUE(all.equal(incantation::bbox(c1, 1),
                             incantation::bbox(replay, 1), tolerance = 1e-10)))
  restored = incantation::align_left(c1, 1, 3)
  stopifnot(isTRUE(all.equal(incantation::bbox(c0, 1),
                             incantation::bbox(restored, 1), tolerance = 1e-10)))
  for (i in 2:6) stopifnot(identical(incantation::bbox(c0, i), incantation::bbox(c1, i)))

  scenes = list(A = a, C_before = c0, C_micro = c1, C_restored = restored, C_replay = replay)
  for (name in names(scenes)) for (ext in c("pdf", "png", "svg")) {
    incantation::ggsave_incant(scenes[[name]], file.path(out, paste0(name, ".", ext)), res = 450)
  }
  raster = incantation::incant(plots$C, width = 96, height = 53.6, units = "mm",
                               device = "ragg", family = "Arial", res = 450, plot_ids = ids)
  incantation::ggsave_incant(raster, file.path(out, "C_ragg.png"))
  elements = incantation::inspect(c0)
  elements$path = vapply(elements$path, paste, character(1), collapse = "/")
  utils::write.csv(elements, file.path(out, "C_elements.csv"), row.names = FALSE)
  slot = c0$registry[["plot-1"]]$parts[[1]]$base
  list(input_md5 = original_hash, canvas_mm = c(96, 53.6), micro_dx_mm = .7,
       target_outer_before_pt = as.list(slot),
       target_data_before_pt = unclass(incantation::bbox(c0, 1)),
       target_data_after_pt = unclass(incantation::bbox(c1, 1)),
       sibling_coordinates_unchanged = TRUE, restored_coordinates_match = TRUE,
       replay_coordinates_match = TRUE, package_version = as.character(packageVersion("incantation")))
}, warning = function(w) {
  stop(conditionMessage(w), call. = FALSE)
})
stopifnot(identical(original_hash, unname(tools::md5sum(bundle))))
record$warnings = character()
jsonlite::write_json(record, file.path(out, "real_panel_checks.json"),
                      auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("PASS: real A/C, Arial exports, 0.7 mm edit, sibling preservation, alignment recovery and replay\n")
