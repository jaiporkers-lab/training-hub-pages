# Training Hub artwork

The forest-green and lime pulse mark matches the [Training Hub project site](https://jaiporkers-lab.github.io/training-hub-pages/). The Dock icon adds the TH monogram.

`AppIcon.svg` and `TH-Logo.svg` are editable vectors. From the project root, run `swift scripts/render-brand.swift Resources/Brand` and `iconutil -c icns Resources/Brand/AppIcon.iconset -o Resources/AppIcon.icns` to regenerate the PNGs and Mac icon. The sidebar draws the pulse natively in SwiftUI.
