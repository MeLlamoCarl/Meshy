# Notices and attributions

## Origin

**Meshy** is a fork of **[Acrylic](https://github.com/EthanLipnik/Acrylic)** by
**Ethan Lipnik**, based on the `2.0.0` tag. The original commit history is kept intact in this
repository; changes made in this fork start after commit `b2e0a90` ("add readme").

- Original work: Copyright (c) 2023 Ethan Lipnik — MIT License
- Fork modifications: Copyright (c) 2026 MeLlamoCarl — MIT License

See [`LICENSE.txt`](LICENSE.txt) for the full license text.

This fork is **not affiliated with, endorsed by, or supported by Ethan Lipnik**. Please report
issues with this fork here, not on the original repository.

Meshy has its own name, icon and artwork. The MIT License covers the source code; it does not grant
trademark rights, and "Acrylic" refers only to the original project.

## Bundled packages (git submodules)

| Package | Fork | Original | License |
|---------|------|----------|---------|
| MeshKit | [MeLlamoCarl/MeshKit](https://github.com/MeLlamoCarl/MeshKit) | [EthanLipnik/MeshKit](https://github.com/EthanLipnik/MeshKit) | MIT |
| PixabayKit | [MeLlamoCarl/PixabayKit](https://github.com/MeLlamoCarl/PixabayKit) | [EthanLipnik/PixabayKit](https://github.com/EthanLipnik/PixabayKit) | MIT — Copyright (c) 2023 Ethan Lipnik |

MeshKit's `LICENSE.txt` was published upstream with a template copyright line
("Scott Chacon and others"); MeshKit itself is the work of Ethan Lipnik and is distributed under
the MIT License.

### Moving Parts — Gradient Meshes with SceneKit

MeshKit's gradient mesh implementation is based on
[Gradient Meshes with SceneKit](https://github.com/movingparts-io/Gradient-Meshes-with-SceneKit) by
[Moving Parts](https://movingparts.io/gradient-meshes), distributed under the MIT License:

```
MIT License

Copyright (c) 2021 Moving Parts

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

## Swift Package Manager dependencies

Resolved at build time; their source is not included in this repository. MeshGradient is
resolved from a fork (tag `1.0.10` = upstream `1.0.9` plus a macOS 26 SDK Metal header fix).

| Package | Author | License |
|---------|--------|---------|
| [MeshGradient](https://github.com/MeLlamoCarl/MeshGradient) — fork of [EthanLipnik/MeshGradient](https://github.com/EthanLipnik/MeshGradient), itself a fork of [patskovn/MeshGradient](https://github.com/patskovn/MeshGradient) | Nikita Patskov and others | MIT |
| [RandomColorSwift](https://github.com/onevcat/RandomColorSwift) | Wei Wang (onevcat) | MIT |
| [SDWebImage](https://github.com/SDWebImage/SDWebImage) | Olivier Poitrey and contributors | MIT |
| [SDWebImageSwiftUI](https://github.com/SDWebImage/SDWebImageSwiftUI) | DreamPiggy (lizhuoli1126) and contributors | MIT |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Thomas Zoechling | MIT |

The original project also depended on `EthanLipnik/Sebu`, which has no published license. This
fork replaced it with its own `ResponseCache` and no longer uses Sebu's code.

## Third-party services

Video wallpapers can be downloaded from [Pixabay](https://pixabay.com) through its API. Using the
API requires your own key and is subject to the
[Pixabay API terms](https://pixabay.com/api/docs/) and the
[Pixabay Content License](https://pixabay.com/service/license-summary/). No API key is included in
this repository: each user enters their own in the app (stored only in their Mac's preferences).
As the API terms require, the Manage Videos window credits Pixabay with a link whenever search
results are shown, and links each video to its Pixabay page and author. The Video wallpaper
thumbnail is a preview of [video 67358](https://pixabay.com/videos/id-67358/) by Engin_Akyurt,
used under the Pixabay Content License.
