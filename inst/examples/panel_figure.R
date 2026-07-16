# Reproducible Incantation layout example with embedded neutral data ----
#
# This script preserves the structure and dimensions of the original plotting
# example while replacing all domain-specific concepts with fictional software
# platform modules, operational metrics, and improvement initiatives.
#
# The example is intended for testing post-layout movement of `p_cluster_c`.

suppressPackageStartupMessages({
  library(tidyverse)
  library(patchwork)
})

theme_axis_big = function(size = 14, linewidth = 0.75, border = FALSE) {
  if (!border) {
    theme(
      axis.text = element_text(size = size, color = "black"),
      axis.line = element_line(linewidth = linewidth),
      axis.title = element_text(color = "black", size = size + 4),
      plot.title = element_text(
        color = "black",
        size = size + 4,
        hjust = 0.5
      ),
      text = element_text(family = "Arial")
    )
  } else {
    theme(
      axis.text = element_text(size = size, color = "black"),
      axis.title = element_text(color = "black", size = size + 4),
      plot.title = element_text(hjust = 0.5, size = size + 4),
      panel.border = element_rect(
        color = "black",
        linewidth = linewidth,
        fill = NA
      ),
      axis.line = element_blank(),
      text = element_text(family = "Arial")
    )
  }
}

savegg = function(plot, filename, width = NA, height = NA, ...) {
  dir.create(dirname(filename), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    filename,
    plot = plot,
    width = width,
    height = height,
    ...
  )
}

dir.create(
  "./result/incantation_demo",
  recursive = TRUE,
  showWarnings = FALSE
)

normalize_metric_panel = function(metric_panel, module_levels) {
  imap_dfr(metric_panel, \(metrics, module_name) {
    tibble(
      module = module_name,
      metric = metrics,
      metric_order = seq_along(metrics)
    )
  }) |>
    filter(module %in% module_levels) |>
    mutate(
      module = factor(module, levels = module_levels),
      feature_order = row_number(),
      feature = paste(module, metric, feature_order, sep = "::")
    )
}

module_levels_c = c(
  "Search_Ranking",
  "Payments_Checkout",
  "Messaging_Realtime",
  "Storage_Archive",
  "Analytics_Batch",
  "Compute_Autoscale",
  "Identity_Access",
  "Monitoring_Alerts",
  "Support_Automation"
)

metric_panel = list(
  Search_Ranking = c(
    "QueryLatency",
    "RecallRate",
    "ClickYield",
    "CacheHit",
    "IndexFreshness",
    "ResultDiversity"
  ),
  Payments_Checkout = c(
    "AuthSuccess",
    "RetryRate",
    "GatewayTime",
    "FraudScreen",
    "CartRecovery",
    "SettlementLag"
  ),
  Messaging_Realtime = c(
    "DeliveryRate",
    "QueueDepth",
    "FanoutTime",
    "ReconnectRate",
    "PacketLoss",
    "AckLatency"
  ),
  Storage_Archive = c(
    "ReadThroughput",
    "WriteThroughput",
    "CompressionRate",
    "RestoreTime",
    "ObjectCount",
    "ReplicationLag"
  ),
  Analytics_Batch = c(
    "JobRuntime",
    "SlotUse",
    "ShuffleVolume",
    "CacheReuse",
    "FailureRate",
    "DataFreshness"
  ),
  Compute_Autoscale = c(
    "CpuHeadroom",
    "MemoryHeadroom",
    "ScaleOutTime",
    "ScaleInTime",
    "NodeChurn",
    "WarmPool"
  ),
  Identity_Access = c(
    "LoginSuccess",
    "TokenLatency",
    "PolicyChecks",
    "SessionReuse",
    "LockoutRate",
    "KeyRotation"
  ),
  Monitoring_Alerts = c(
    "AlertPrecision",
    "AlertRecall",
    "NoiseRate",
    "DetectTime",
    "EscalationTime",
    "Coverage"
  ),
  Support_Automation = c(
    "DeflectionRate",
    "ResolutionTime",
    "HandoffRate",
    "ReplyLatency",
    "Satisfaction",
    "ReopenRate"
  )
)

# Fictional effect scores for a software-platform comparison.
# These values are synthetic and contain no customer or production information.
df_effect_platform_panel = tibble::tribble(
  ~module, ~metric, ~effect_score,
  "Search_Ranking", "QueryLatency", 2.7,
  "Search_Ranking", "RecallRate", 2.4,
  "Search_Ranking", "ClickYield", 2.1,
  "Search_Ranking", "CacheHit", 2.9,
  "Search_Ranking", "IndexFreshness", 2.3,
  "Search_Ranking", "ResultDiversity", 3.1,
  "Payments_Checkout", "AuthSuccess", 3.4,
  "Payments_Checkout", "RetryRate", 2.8,
  "Payments_Checkout", "GatewayTime", 2.2,
  "Payments_Checkout", "FraudScreen", 1.9,
  "Payments_Checkout", "CartRecovery", 3.0,
  "Payments_Checkout", "SettlementLag", 3.2,
  "Messaging_Realtime", "DeliveryRate", 3.6,
  "Messaging_Realtime", "QueueDepth", 3.0,
  "Messaging_Realtime", "FanoutTime", 2.7,
  "Messaging_Realtime", "ReconnectRate", 2.9,
  "Messaging_Realtime", "PacketLoss", 3.3,
  "Messaging_Realtime", "AckLatency", 2.5,
  "Storage_Archive", "ReadThroughput", 2.0,
  "Storage_Archive", "WriteThroughput", 1.7,
  "Storage_Archive", "CompressionRate", 1.5,
  "Storage_Archive", "RestoreTime", 1.8,
  "Storage_Archive", "ObjectCount", 2.4,
  "Storage_Archive", "ReplicationLag", 2.9,
  "Analytics_Batch", "JobRuntime", 1.4,
  "Analytics_Batch", "SlotUse", 2.1,
  "Analytics_Batch", "ShuffleVolume", 1.2,
  "Analytics_Batch", "CacheReuse", 1.5,
  "Analytics_Batch", "FailureRate", 2.3,
  "Analytics_Batch", "DataFreshness", 1.8,
  "Compute_Autoscale", "CpuHeadroom", 1.9,
  "Compute_Autoscale", "MemoryHeadroom", 2.8,
  "Compute_Autoscale", "ScaleOutTime", 1.6,
  "Compute_Autoscale", "ScaleInTime", 1.3,
  "Compute_Autoscale", "NodeChurn", 2.2,
  "Compute_Autoscale", "WarmPool", 3.0,
  "Identity_Access", "LoginSuccess", 2.6,
  "Identity_Access", "TokenLatency", 1.8,
  "Identity_Access", "PolicyChecks", 2.4,
  "Identity_Access", "SessionReuse", 1.1,
  "Identity_Access", "LockoutRate", 1.7,
  "Identity_Access", "KeyRotation", 2.0,
  "Monitoring_Alerts", "AlertPrecision", 2.2,
  "Monitoring_Alerts", "AlertRecall", 2.7,
  "Monitoring_Alerts", "NoiseRate", 1.9,
  "Monitoring_Alerts", "DetectTime", 1.6,
  "Monitoring_Alerts", "EscalationTime", 1.2,
  "Monitoring_Alerts", "Coverage", 2.5,
  "Support_Automation", "DeflectionRate", 2.0,
  "Support_Automation", "ResolutionTime", 2.8,
  "Support_Automation", "HandoffRate", 2.3,
  "Support_Automation", "ReplyLatency", 1.5,
  "Support_Automation", "Satisfaction", 1.7,
  "Support_Automation", "ReopenRate", 2.1
)

df_metric_panel = normalize_metric_panel(
  metric_panel,
  module_levels_c
)

df_heat_platform = expand_grid(
  module = module_levels_c,
  df_metric_panel |>
    select(
      source_module = module,
      metric,
      feature,
      feature_order
    )
) |>
  left_join(
    df_effect_platform_panel,
    by = c("module", "metric")
  ) |>
  mutate(
    effect_score = replace_na(effect_score, 0),
    module = factor(module, levels = module_levels_c),
    feature = factor(
      feature,
      levels = rev(df_metric_panel$feature)
    )
  )

df_feature_label_c = df_metric_panel |>
  distinct(feature, metric)

# Fictional improvement initiatives and synthetic relevance values.
df_initiative_platform = tibble::tribble(
  ~module, ~initiative, ~relevance,
  "Search_Ranking", "Search relevance optimization", 1e-8,
  "Search_Ranking", "Index freshness management", 1e-6,
  "Search_Ranking", "Query cache efficiency", 1e-4,
  "Payments_Checkout", "Checkout reliability", 1e-8,
  "Payments_Checkout", "Fraud screening workflow", 1e-6,
  "Payments_Checkout", "Settlement processing", 1e-4,
  "Messaging_Realtime", "Realtime delivery stability", 1e-8,
  "Messaging_Realtime", "Queue backpressure control", 1e-6,
  "Messaging_Realtime", "Connection recovery", 1e-4,
  "Storage_Archive", "Read and write efficiency", 1e-8,
  "Storage_Archive", "Archive compression workflow", 1e-6,
  "Storage_Archive", "Replication resilience", 1e-4,
  "Analytics_Batch", "Batch scheduling efficiency", 1e-8,
  "Analytics_Batch", "Distributed shuffle control", 1e-6,
  "Analytics_Batch", "Dataset freshness", 1e-4,
  "Compute_Autoscale", "Autoscaling responsiveness", 1e-8,
  "Compute_Autoscale", "Capacity headroom planning", 1e-6,
  "Compute_Autoscale", "Node lifecycle stability", 1e-4,
  "Identity_Access", "Authentication reliability", 1e-8,
  "Identity_Access", "Access policy evaluation", 1e-6,
  "Identity_Access", "Credential rotation", 1e-4,
  "Monitoring_Alerts", "Alert quality improvement", 1e-8,
  "Monitoring_Alerts", "Incident detection coverage", 1e-6,
  "Monitoring_Alerts", "Escalation response", 1e-4,
  "Support_Automation", "Ticket deflection workflow", 1e-8,
  "Support_Automation", "Automated response quality", 1e-6,
  "Support_Automation", "Human handoff efficiency", 1e-4
) |>
  mutate(
    module = factor(module, levels = module_levels_c),
    score = -log10(relevance)
  )

module_color_table = c(
  Search_Ranking = "#4C78A8",
  Payments_Checkout = "#F58518",
  Messaging_Realtime = "#E45756",
  Storage_Archive = "#72B7B2",
  Analytics_Batch = "#54A24B",
  Compute_Autoscale = "#EECA3B",
  Identity_Access = "#B279A2",
  Monitoring_Alerts = "#FF9DA6",
  Support_Automation = "#9D755D"
)

heat_colors_c = c(
  "#2166AC",
  "#4393C3",
  "#92C5DE",
  "#D1E5F0",
  "#F7F7F7",
  "#FDDBC7",
  "#F4A582",
  "#D6604D",
  "#B2182B"
)

module_colors_c = module_color_table[module_levels_c]

p_heat_c = df_heat_platform |>
  ggplot(aes(module, feature, fill = effect_score)) +
  geom_tile(color = "white") +
  scale_fill_gradientn(
    colors = heat_colors_c,
    limits = c(-4, 4),
    breaks = c(-4, 0, 4),
    oob = scales::squish
  ) +
  scale_y_discrete(
    labels = setNames(
      df_feature_label_c$metric,
      df_feature_label_c$feature
    )
  ) +
  labs(
    x = NULL,
    y = NULL,
    fill = "Effect score"
  ) +
  theme_bw() +
  theme_axis_big(12, 0.75, border = TRUE) +
  theme(
    legend.position = "top",
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank(),
    panel.grid = element_blank(),
    plot.margin = margin(0.2, 0.2, 0, 0.2, "cm"),
    legend.key.size = unit(0.5, "cm"),
    legend.key.width = unit(0.5, "cm"),
    legend.title = element_text(size = 12),
    legend.text = element_text(size = 8)
  )

# This is the subplot used to demonstrate Incantation's post-layout translation.
p_cluster_c = tibble(
  module = factor(module_levels_c, levels = module_levels_c)
) |>
  arrange(module) |>
  mutate(
    label = c(
      "Ranking",
      "Checkout",
      "Realtime",
      "Archive",
      "Batch",
      "Autoscale",
      "Access",
      "Alerts",
      "Automation"
    )
  ) |>
  ggplot(aes(x = module, color = module)) +
  geom_point(
    aes(y = 1),
    size = 6,
    show.legend = FALSE
  ) +
  geom_text(
    aes(y = 1, label = label),
    angle = 30,
    hjust = 1,
    vjust = 2,
    size = 4,
    color = "black",
    show.legend = FALSE
  ) +
  scale_color_manual(values = module_colors_c) +
  coord_cartesian(clip = "off") +
  theme_axis_big(12, 0.75) +
  theme(
    legend.position = "none",
    panel.background = element_blank(),
    panel.border = element_blank(),
    plot.background = element_blank(),
    plot.margin = margin(0, 0, 45, 0, "pt"),
    axis.text = element_blank(),
    axis.title = element_blank(),
    axis.ticks = element_blank(),
    axis.line = element_blank(),
    panel.grid = element_blank()
  )

p_enrich_c = df_initiative_platform |>
  ggplot(
    aes(
      reorder(initiative, score),
      score,
      fill = module
    )
  ) +
  geom_col(width = 0.75, show.legend = FALSE) +
  scale_x_discrete(position = "top") +
  facet_wrap(
    ~ module,
    ncol = 1,
    scales = "free_y"
  ) +
  coord_flip() +
  scale_fill_manual(values = module_colors_c) +
  scale_y_continuous(expand = c(0, 0)) +
  labs(
    x = NULL,
    y = "-Log10(Relevance)"
  ) +
  theme_bw() +
  theme_axis_big(12, 0.75, border = TRUE) +
  theme(
    strip.background = element_blank(),
    strip.text = element_blank(),
    axis.title.y = element_blank(),
    panel.spacing = unit(0, "lines"),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank()
  )

p_c = (
  p_heat_c +
    p_enrich_c +
    p_cluster_c +
    plot_spacer()
) +
  plot_layout(
    widths = c(2, 1),
    heights = c(9, 1)
  )

p_c

