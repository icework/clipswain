# Third-party notices

## Paperclip

The palette identifiers and gradient stops in `App/Components/Design.swift` are adapted from Paperclip's `CAP_V1_COLORS` data. Paperclip is developed by Paperclip AI and distributed under the MIT License. The upstream notice is reproduced below.

Source: [paperclipai/paperclip](https://github.com/paperclipai/paperclip), [license snapshot](https://github.com/paperclipai/paperclip/blob/0fb152ee9493075354fbe9b813c7f2f256f22a52/LICENSE).

```text
MIT License

Copyright (c) 2025 Paperclip AI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## ClipLab cap-v1 artwork and palettes

`Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` was rendered by Paperclip's avatar endpoint with the `cap-v1` character, `solar-flare` palette, `idle` pose, `size=512`, `scale=2`, and `paperclip-dark` background. `Resources/Assets.xcassets/BrandMark.imageset/BrandMark.png` is a 512-pixel resized derivative of that icon. These are derived upstream artwork, not original artwork created for this client.

The endpoint uses Paperclip's [avatar route](https://github.com/paperclipai/paperclip/blob/0fb152ee9493075354fbe9b813c7f2f256f22a52/server/src/routes/agent-avatars.ts), [worker](https://github.com/paperclipai/paperclip/blob/0fb152ee9493075354fbe9b813c7f2f256f22a52/server/src/services/agent-avatar-worker.ts), and [ClipLab static renderer](https://github.com/paperclipai/paperclip/blob/0fb152ee9493075354fbe9b813c7f2f256f22a52/packages/shared/src/cliplab/static.ts). The palette values adapted in `App/Components/Design.swift` also appear in [cap-v1 palette tokens](https://github.com/paperclipai/paperclip/blob/0fb152ee9493075354fbe9b813c7f2f256f22a52/packages/shared/src/cliplab/palette-tokens.ts).

Paperclip's [ClipLab provenance](https://github.com/paperclipai/paperclip/blob/0fb152ee9493075354fbe9b813c7f2f256f22a52/packages/shared/src/cliplab/PROVENANCE.md) identifies [tonio-alucema/cliplab](https://github.com/tonio-alucema/cliplab), release `v0.2.0`, commit `987b6db049471df815ebcb88bcd7abb46ed0c34b`, under MIT. It identifies the [Cliptoon color library](https://cliptoon-color-library.vercel.app/) as the palette source. The separate [ClipLab MIT notice](https://github.com/paperclipai/paperclip/blob/0fb152ee9493075354fbe9b813c7f2f256f22a52/packages/shared/src/cliplab/LICENSE) is retained below in addition to Paperclip's notice above. No trademark authorization or official endorsement is implied.

```text
MIT License

Copyright (c) 2026 Jérémy Perret (bloub, the project this is forked from)
Copyright (c) 2026 Tonio (Cliplab, modifications)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Frameworks, services, and names

The app uses Apple's system frameworks and SF Symbols under Apple's applicable terms. PaperclipKit currently has no external Swift Package dependencies. Paperclip, Apple, and model-provider names identify interoperability; this project is not an official client endorsed by those organizations. The MIT license does not grant trademark rights or rights to the content returned by a connected server.
