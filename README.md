# SF2Player

Player de SoundFont (.sf2) nativo para macOS (Swift + AppKit), compatível com macOS 10.15+ (Intel e Apple Silicon).

- Lê os presets do arquivo `.sf2` (chunk RIFF `pdta/phdr`) e lista em um menu suspenso
- Áudio com `AVAudioEngine` + `AVAudioUnitSampler`
- Teclado virtual (mouse e teclado do computador) e controladores MIDI USB via CoreMIDI
- Volume master e botão Panic (All Notes Off)

## Compilar na nuvem
Faça push para o GitHub. O workflow `.github/workflows/build-macos.yml` gera `SF2Player-macOS.zip`
(em *Actions → Artifacts* e, para tags `v*`, em *Releases*).

## Compilar localmente (se tiver um Mac)
```bash
bash scripts/build_app.sh
open build/SF2Player.app
```

## Primeira abertura no Mac
O app é assinado de forma ad-hoc (sem conta Apple Developer). Se o macOS bloquear:
clique com o botão direito no app → **Abrir**, ou rode `xattr -cr SF2Player.app` no Terminal.
