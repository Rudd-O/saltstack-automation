#!objects

include("rpmfusion")

Pkg.installed(
    "GStreamer",
    pkgs=[
        "gstreamer1",
        "gstreamer1-plugins-base",
        "gstreamer1-plugins-base-tools",
        "gstreamer1-plugins-good",
        "gstreamer1-plugins-good-extras",
        "gstreamer1-plugins-good-gtk",
        "gstreamer1-plugins-good-qt",
        "gstreamer1-plugins-ugly",
        "gstreamer1-plugins-bad-free",
        "gstreamer1-plugins-bad-free-extras",
        "gstreamer1-plugins-bad-freeworld",
        "gstreamer1-vaapi",
        #   libav is the codec needed to make firefox h.264 work
        #   but it does not seem to be installable anymore
        # "gstreamer1-libav.x86_64",
    ],
    require=[Test("RPMFusion setup")],
).requisite
