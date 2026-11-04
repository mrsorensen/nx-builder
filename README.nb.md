# NX Builder (norsk)

**Bygg Switch-spillene du eier om til Mac-apper med [nxnative](https://github.com/seedds/nxnative), uten Terminal.**

NX Builder er en liten, gratis Mac-app oppå nxnative. Du velger en spillfil, trykker **Bygg spillet**, og får en
Mac-app av spillet du kan dobbeltklikke på. Appen er på norsk når Macen er på norsk, ellers på engelsk.
Den fulle beskrivelsen står i [README.md](README.md) (engelsk).

> NX Builder inneholder ingen spill, nøkler eller annet fra Nintendo, og lenker ikke til noe slikt. Du trenger dumper
> av spill du eier og `prod.keys` fra din egen Switch. NX Builder har ingen tilknytning til Nintendo, og er et eget
> prosjekt ved siden av nxnative: meld feil i NX Builder her, ikke til nxnative.

## Kort fortalt

1. **Installer:** last ned zip-filen fra Releases, pakk den ut og flytt **NX Builder** til Programmer. Første gang
   nekter macOS å åpne den (den er ikke notarisert). Prøv å åpne den, gå så til **Systeminnstillinger ›
   Personvern og sikkerhet** og klikk **Åpne likevel**. Eller bygg den selv med `./build.sh --install`.
2. **Oppsett:** fiks de røde linjene ovenfra og ned. Knappene laster ned nxnative, setter opp Python og installerer
   Metal-verktøyene; resten har en kommando du kopierer inn i Terminal.
3. **Bygg:** velg spillfilen eller mappen. Grunnspill og oppdatering skal i samme mappe, i versjonen spillets
   oppskrift er laget for (se listen over spill med oppskrift).
4. **Spill:** første start tar noen minutter mens macOS viser «Verifiserer …». Senere starter tar sekunder.

Tastatur: W A S D går, Shift + piltaster styrer kameraet, J K U I er A B X Y, Q/E er L/R, Z/C er ZL/ZR,
Return/Tab er +/−. Kontrollere (Xbox, PlayStation, Switch Pro, 8BitDo) virker med en gang.
