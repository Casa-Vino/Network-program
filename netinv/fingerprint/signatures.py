"""Device signature database.

Each signature is a set of conditions; a device scores points for every
condition it satisfies (see engine.DEFAULT_POINTS). The best-scoring
signature above a threshold becomes the device's classification. This is a
small, hand-written seed set -- the format is designed to grow, and real
coverage would come from importing a larger dataset into this same shape.

Condition keys (all optional, all case-insensitive substring/set tests):
    oui_vendor            any substring in the resolved/SSDP manufacturer
    model_contains        any substring in model + friendlyName
    friendly_name_contains any substring in friendlyName
    device_type_contains  any substring in the SSDP deviceType URNs
    services_any          any of these mDNS service types present
    services_all          all of these mDNS service types present

`notes` is informational only -- where the admin interface tends to live or
how the class is provisioned. It is never a credential.
"""

SIGNATURES = [
    {
        "label": "Internet gateway / router",
        "category": "gateway / router",
        "device_type_contains": ["internetgatewaydevice", "wandevice",
                                 "wanconnectiondevice"],
        "notes": "web admin on http/https at this IP; modern units ship a "
                 "unique password on the label",
    },
    {
        "label": "Apple TV",
        "category": "media / airplay",
        "oui_vendor": ["apple"],
        "services_any": ["_airplay._tcp.local", "_raop._tcp.local",
                         "_mediaremotetv._tcp.local"],
        "model_contains": ["apple tv"],
    },
    {
        "label": "Google Cast device",
        "category": "media renderer",
        "services_any": ["_googlecast._tcp.local"],
    },
    {
        "label": "Sonos speaker",
        "category": "speaker",
        "oui_vendor": ["sonos"],
        "services_any": ["_sonos._tcp.local", "_spotify-connect._tcp.local"],
    },
    {
        "label": "Network printer",
        "category": "printer",
        "services_any": ["_ipp._tcp.local", "_ipps._tcp.local",
                         "_printer._tcp.local", "_pdl-datastream._tcp.local"],
        "device_type_contains": ["printer"],
        "notes": "web admin + IPP; often has an unauthenticated status page",
    },
    {
        "label": "HomeKit accessory",
        "category": "homekit accessory",
        "services_any": ["_hap._tcp.local"],
    },
    {
        "label": "Philips Hue bridge",
        "category": "iot hub",
        "oui_vendor": ["philips", "signify"],
        "services_any": ["_hue._tcp.local", "_hap._tcp.local"],
        "friendly_name_contains": ["hue"],
    },
    {
        "label": "Synology NAS",
        "category": "file server / nas",
        "oui_vendor": ["synology"],
        "services_any": ["_smb._tcp.local", "_afpovertcp._tcp.local",
                         "_http._tcp.local"],
        "notes": "DSM web admin, typically on :5000/:5001",
    },
    {
        "label": "Raspberry Pi",
        "category": "host (linux)",
        "oui_vendor": ["raspberry pi"],
        "services_any": ["_ssh._tcp.local", "_sftp-ssh._tcp.local"],
    },
    {
        "label": "Ubiquiti device",
        "category": "network infrastructure",
        "oui_vendor": ["ubiquiti"],
        "notes": "UniFi/EdgeOS web admin; may be adopted by a controller",
    },
    {
        "label": "ESP / IoT microcontroller",
        "category": "iot device",
        "oui_vendor": ["espressif"],
    },
    {
        "label": "SMB / AFP file share",
        "category": "file server / nas",
        "services_any": ["_smb._tcp.local", "_afpovertcp._tcp.local"],
    },
    {
        "label": "SSH host",
        "category": "host",
        "services_any": ["_ssh._tcp.local", "_sftp-ssh._tcp.local"],
    },
]
