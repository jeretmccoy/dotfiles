# AstroNvim configuration

This is a separate AstroNvim v6 configuration based on the official template.
The root `install.sh` links it to `~/.config/astronvim`, and the `astro` shell alias starts it with:

```sh
NVIM_APPNAME=astronvim nvim
```

The separate application name keeps AstroNvim's configuration, plugins, state, and cache isolated from the default Neovim setup.
