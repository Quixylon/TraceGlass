# Changelog

## 1.0.0 — 2026-09-15

Первый релиз бесплатного нативного приложения TraceGlass.

### Добавлено

- Lightbox: импорт Photos / Files / Camera / Clipboard, PNG/JPEG/HEIC и отдельные страницы PDF.
- Одновременные перемещение, масштаб и поворот, зеркалирование, Snap и быстрые команды.
- Lock с запретом изменений в модели, фиксированным кадром и Hold to Unlock.
- Яркость, предотвращение сна на время сеанса, восстановление яркости и предупреждение о нагреве.
- Core Image: тональные настройки, grayscale, invert, threshold, edges, cleanup и Prepare for Tracing.
- Original preview, Before/After, фоны, сетки, линейки, калибровка размера и ручные tiles.
- До пяти слоёв, crop / perspective, проекты, autosave, undo/redo.
- Paper Track на AVFoundation/Vision и World Anchor на ARKit/RealityKit.
- Ghost, reference toggle, Overhead, ручные углы и опциональная person occlusion в World Anchor.
- Нативный Liquid Glass на iOS 26+, системный материал на iOS 17–18.
- Metal-переходы из изображения в AR и обратно, Reduce Motion.
- Сборка arm64/iphoneos, проверка Mach-O, XCTest/XCUITest и автоматическая публикация GitHub Release.

### Проверка и ограничения

Базовый код прошёл 17 тестов на iOS 26.2 Simulator, включая Lock и landscape. CI каждого релиза повторно собирает приложение и запускает тесты перед публикацией. Реальные камера, AR, 120 FPS и установка после resign требуют проверки на физическом iPhone. Полный список: [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).
