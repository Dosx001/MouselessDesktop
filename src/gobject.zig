const gtk = @import("gtk");

pub fn gSignalConnect(
    instance: gtk.gpointer,
    detailed_signal: [*c]const gtk.gchar,
    c_handler: gtk.GCallback,
    data: gtk.gpointer,
) void {
    _ = gtk.g_signal_connect_data(
        instance,
        detailed_signal,
        c_handler,
        data,
        null,
        0,
    );
}
