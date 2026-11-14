# TikTok Mod (iPad)

Made by Mistrzel

Aplikacja Flutter: TikTok w WebView + menu Mody (ikona suwaków).

## Mody
- Pobierz film bez znaku wodnego (do Zdjec)
- Pobierz dzwiek MP3 (otwiera menu udostepniania -> "Zapisz w Plikach")
- Pokaz kanal / Otworz kanal autora
- Kopiuj czysty link (bez parametrow sledzacych)
- Kopiuj opis filmu
- Ulubione (zapisane lokalnie w aplikacji)
- Predkosc odtwarzania 0.5x / 1x / 1.5x / 2x
- Auto-nastepny film
- Wersja mobilna / komputerowa strony

Wiekszosc modow dziala na filmie, ktory jest otwarty (adres z /video/).
Jesli mod mowi "Otworz film", kliknij film i sprobuj ponownie.

## Jak zrobic .ipa (bez Maca)
1. Zaloz konto na github.com i utworz NOWE repozytorium (np. tiktok-mod).
2. Wrzuc tam zawartosc tego zipa (razem z ukrytym folderem .github).
3. Wejdz w zakladke Actions -> "Build IPA" -> Run workflow.
4. Po kilku minutach otworz zakonczone zadanie i pobierz artifact "TikTokMod-ipa".
5. Rozpakuj go - w srodku jest TikTokMod.ipa.
6. Wgraj go na iPada przez Sideloadly (darmowe Apple ID, odnawianie co 7 dni).

## Tryb developera (banery)
Menu Mody -> "Tryb developera" (domyslny PIN: 1234 - zmien go w menu!).
- Dodajesz banery (tekst, kolor, gora/dol, czy mozna zamknac).
- Banery pokazuja sie nad TikTokiem w Twojej aplikacji (iPad i iPhone).
- Zeby ten sam baner widzialy WSZYSTKIE Twoje urzadzenia: "Kopiuj JSON banerow",
  wklej do pliku banners.json na GitHubie (patrz banners.example.json), wez adres
  "Raw" tego pliku i wpisz go w "Adres JSON (zdalne banery)".
  Aplikacja pobiera ten plik przy kazdym starcie.
- Baner nie pojawi sie w oficjalnej aplikacji TikTok ani u innych ludzi.

## iPhone i iPad
Ten sam plik .ipa dziala na obu urzadzeniach (iOS 13+). Wgraj go Sideloadly osobno na kazdy.
