-- Monitor layout. Left alone, Hyprland auto-detects and enables every output
-- at its preferred mode. Run `nwg-displays` for a GUI editor -- it rewrites
-- this exact file (and monitors.conf, which qml-rice-dots does not use).
--
-- Generic fallback: enable everything at its preferred mode and resolution,
-- automatically positioned.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1
})

-- Example of a specific, multi-output layout (edit and uncomment):
-- hl.monitor({
--     output = "DP-1",
--     mode = "1920x1080@60.0",
--     position = "0x0",
--     scale = 1,
--     vrr = 0
-- })
-- hl.monitor({
--     output = "HDMI-A-1",
--     mode = "1920x1080@60.0",
--     position = "1920x0",
--     scale = 1,
--     vrr = 0
-- })
