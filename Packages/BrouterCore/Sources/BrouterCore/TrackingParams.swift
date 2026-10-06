/// Query parameters that exist only for click attribution and never affect what a page shows.
public enum TrackingParams {
    public static let builtIn: [String] = [
        "utm_*",
        "fbclid", "igshid",
        "gclid", "dclid", "gbraid", "wbraid",
        "msclkid", "yclid", "twclid", "ttclid", "li_fat_id",
        "mc_eid", "mc_cid",
        "_hsenc", "_hsmi",
        "oly_enc_id", "oly_anon_id",
        "vero_id", "rb_clickid", "s_cid",
        "si",
    ]
}
