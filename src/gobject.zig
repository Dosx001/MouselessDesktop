const c = @cImport({
    @cInclude("glib-object.h");
});

pub fn g_signal_connect(
    instance: c.gpointer,
    detailed_signal: [*c]const c.gchar,
    c_handler: c.GCallback,
    data: c.gpointer,
) void {
    _ = c.g_signal_connect_data(
        instance,
        detailed_signal,
        c_handler,
        data,
        null,
        0,
    );
}
