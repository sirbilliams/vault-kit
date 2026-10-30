# vault-kit

Shared mobile UI library (drawing, themes, skins, widgets, touch layout) for the
Fallout 1 CE and Fallout 2 CE dual-screen Android ports.

Status: v0 - extraction in progress. Nothing usable yet.

## Use

Consumed as a git submodule at `third_party/vault-kit`, pinned by tag
(`git submodule add <url> third_party/vault-kit`, then check out a tag).
CMake: `add_subdirectory(third_party/vault-kit)`.

## The vk::Host adapter

- The kit owns drawing, themes (Classic / Pip-Boy), skins, widgets and layout.
- Each port implements one `vk::Host` interface once (`host_f1.cc` / `host_f2.cc`).
- Host supplies: SDL renderer/window, FRM art + palette, fonts and charset, settings, touch events.
- Host also supplies value-only snapshot/command structs, so the kit never touches engine pointers.
- No game art is in this repo; art loads at runtime from the user's install.

## Tools

`tools/golden.sh capture|compare` records and compares screenshot goldens
(stored outside this repo because they contain game art).

## License

Sustainable Use License v1.0, see LICENSE.md and NOTICE.md.
