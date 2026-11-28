# G1 — native macOS acceptance artifacts (`c82ff86`, 2026-11-27)

These are the native artifacts of the owner's G1 acceptance runs. They are **native evidence**, kept separate from the sandbox evidence. The analysis is in `docs/evidence/G1.md` (the G1 summary; it was `docs/evidence/SUMMARY.md` until G2), under "Native acceptance". The filled checklist is `docs/acceptance/G1-macos.md`.

The files are stored outside Git and outside `build/`, in `native-evidence/g1-final-native-acceptance-c82ff86-2026-11-27/`. They were copied unchanged (`cp -p`) from the owner's `build/` before any further sandbox run, and `make evidence` copies them into the evidence package. The provenance of each folder is in the folder's `README.txt`:

| Folder | Source | Content |
|---|---|---|
| `run-a-make-check-2213/` | `build/native-g1-IZJY3N/` | the full `make check` run |
| `run-b-smoke-hidpi-2316/` | `build/` | a second smoke and HiDPI harness run, with no console log on disk |
| `aborted-2212/` | `build/native-g1-Dvy0MH/` | a 0-byte log |

Host: Apple M3 Pro, Retina DPI 2.00, renderer `OpenGL / 4.1 Metal - 91.7 / Apple / Apple M3 Pro`.

`make evidence` checks each of these hashes against this file. The `SHA256SUMS` file itself has SHA-256 `74133cbf9bf61b019a731a6cb504209063fdfeecaadd057b0c779d754ce7aa99`.

```
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  ./aborted-2212/native-check.log
1ea32132eae5e9d5d881dfc6487391426819fa39b81c0186636e38d5ea1355f5  ./run-a-make-check-2213/hidpi-sim/fit-dpi1-window.png
1ea32132eae5e9d5d881dfc6487391426819fa39b81c0186636e38d5ea1355f5  ./run-a-make-check-2213/hidpi-sim/fit-dpi1.25-window.png
472f6cc6ab65ac8e26c7940f038da7566eedf5dd2bf7b7c034a5c9d53f0351ff  ./run-a-make-check-2213/hidpi-sim/fit-dpi1.25.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/hidpi-sim/fit-dpi1.25.png
1ea32132eae5e9d5d881dfc6487391426819fa39b81c0186636e38d5ea1355f5  ./run-a-make-check-2213/hidpi-sim/fit-dpi1.5-window.png
d16fbdaa2497301fd9f4a96c4d167b3da86bf5494c83c5367248dbb45c950640  ./run-a-make-check-2213/hidpi-sim/fit-dpi1.5.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/hidpi-sim/fit-dpi1.5.png
8245a7ec1c7eb5c7405a6cef1f0e9b15574084120302dcd8507ce09e17c962b2  ./run-a-make-check-2213/hidpi-sim/fit-dpi1.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/hidpi-sim/fit-dpi1.png
1ea32132eae5e9d5d881dfc6487391426819fa39b81c0186636e38d5ea1355f5  ./run-a-make-check-2213/hidpi-sim/fit-dpi2-window.png
9b154ed189c49cbb5c2e365dbe4a53fdf20b16b978ea6d5999c0dcee674b1bd6  ./run-a-make-check-2213/hidpi-sim/fit-dpi2.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/hidpi-sim/fit-dpi2.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-a-make-check-2213/hidpi-sim/integer-dpi1-window.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-a-make-check-2213/hidpi-sim/integer-dpi1.25-window.png
6463ceb2154f1ff0d06859d8303b2ca6cd0103ac8501156329b2c1f78493bd01  ./run-a-make-check-2213/hidpi-sim/integer-dpi1.25.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/hidpi-sim/integer-dpi1.25.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-a-make-check-2213/hidpi-sim/integer-dpi1.5-window.png
af3f3b1b7007f525825682d57d947d4d9e7ea9baf3d57e3f635497ac319904ea  ./run-a-make-check-2213/hidpi-sim/integer-dpi1.5.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/hidpi-sim/integer-dpi1.5.png
351c7604f0183ca85e9053823f2bf5ca3262a58c76de127e6c4d139379c0617b  ./run-a-make-check-2213/hidpi-sim/integer-dpi1.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/hidpi-sim/integer-dpi1.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-a-make-check-2213/hidpi-sim/integer-dpi2-window.png
9752b4f0040f49b79c6da371c12022bade4b797089c58a0701141c30668e1e6b  ./run-a-make-check-2213/hidpi-sim/integer-dpi2.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/hidpi-sim/integer-dpi2.png
cf8c0f3d65437efbf93d757834dd791dae14e0071f6cd2e3b31627daaecdcd6d  ./run-a-make-check-2213/native-check.log
06e5997d50f2da29aeae021413dcfe4e68bb86297e452002509a6c4d2d87da72  ./run-a-make-check-2213/smoke-1024x640-window.png
d07fb3f9374c643711ebd14bf766fa45e5054d3ca139c41ffaab38b5257793ce  ./run-a-make-check-2213/smoke-1024x640.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/smoke-1024x640.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-a-make-check-2213/smoke-1280x720-window.png
99293dc593788b7795d2fd512f8b9853a5f749609f32a729e266aa61e9712b0d  ./run-a-make-check-2213/smoke-1280x720.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/smoke-1280x720.png
e55b6a154d219760886baa24c8cb1620d17b94dd48e69857ba4ee29abc70bed3  ./run-a-make-check-2213/smoke-window.png
85eedefcbed1205d4276282fe79d69c4b3aac9e590b8403a043f361c749924c8  ./run-a-make-check-2213/smoke.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-a-make-check-2213/smoke.png
1ea32132eae5e9d5d881dfc6487391426819fa39b81c0186636e38d5ea1355f5  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi1-window.png
1ea32132eae5e9d5d881dfc6487391426819fa39b81c0186636e38d5ea1355f5  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi1.25-window.png
a1f3ae13f8b252c3140f4e5cd32ecc2a98d3dc1b6ad679f0205147e94d0264b3  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi1.25.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi1.25.png
1ea32132eae5e9d5d881dfc6487391426819fa39b81c0186636e38d5ea1355f5  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi1.5-window.png
f4c9e086ba7b48f5afde9839c3faeeb19bbf9f1042980327794d7a3395f2da27  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi1.5.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi1.5.png
0b392d6680d28bd9a4dfbd342a3eb04e4b5eaefa9a0a02dd7b5c7825d42f6f08  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi1.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi1.png
1ea32132eae5e9d5d881dfc6487391426819fa39b81c0186636e38d5ea1355f5  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi2-window.png
495f4000d3e8d547a02f34076826c51376d59ea71d4940c4b5a09e92c89a2134  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi2.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/hidpi-sim/fit-dpi2.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi1-window.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi1.25-window.png
664356480847976da3ee49cb0f9865211785fe83b352df306a67283d34307c00  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi1.25.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi1.25.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi1.5-window.png
b4849214135dea7573b485b1365b5048182f19c563e0ebceb320fa480fd1e32d  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi1.5.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi1.5.png
d4fe405af02004c948022cb7e51679c2b0f3687f6e1cdfa7c33e3e7715498db3  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi1.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi1.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi2-window.png
d5019d792b4be10ef8a6d74e9cf940f466698461a2a580c2538988490b593d72  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi2.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/hidpi-sim/integer-dpi2.png
06e5997d50f2da29aeae021413dcfe4e68bb86297e452002509a6c4d2d87da72  ./run-b-smoke-hidpi-2316/smoke-1024x640-window.png
55fd74c6bea42bb65706711e22a639868b9925a87df97c0d15c157f6a978fa88  ./run-b-smoke-hidpi-2316/smoke-1024x640.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/smoke-1024x640.png
1d84ce3cafcfb1fc8e44f3c0fb9eb8c17135d358eb78f8bb1c8f3f38676faab4  ./run-b-smoke-hidpi-2316/smoke-1280x720-window.png
14ae4f650a017a192365d4eb9492c7e91c5a7602cdb0e6db8569b798f41a1b76  ./run-b-smoke-hidpi-2316/smoke-1280x720.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/smoke-1280x720.png
e55b6a154d219760886baa24c8cb1620d17b94dd48e69857ba4ee29abc70bed3  ./run-b-smoke-hidpi-2316/smoke-window.png
3f7964be90b9b1ca996e018986d1b8f46477c84f74d5be8b53d06437d62c3486  ./run-b-smoke-hidpi-2316/smoke.log
bdcb578c3b7386c86a412f79ab8fcb817733b68a69d0a93cc244a3676a3ce4c3  ./run-b-smoke-hidpi-2316/smoke.png
```
