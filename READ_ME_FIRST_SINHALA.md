# Early Birds Phone PWA — Android සහ iPhone

මෙය computer එකක Python server එකක් open තබාගන්න අවශ්‍ය නැති, GitHub Pages HTTPS link එකකින් භාවිතා කරන phone-first PWA source package එකයි. Android සහ iPhone Home Screen එකට එක් කළ හැකි manifest, icons, offline shell සහ install උපදෙස් ඇතුළත්ය.

**Backend එක owner අනුමැතියෙන් activate කර ඇත.** Phone gateway සහ account-management function දෙකම ක්‍රියාත්මකයි. GitHub access සාර්ථකව නැවත පරීක්ෂා කර ඇත. Public Pages release status එක `evidence/deployment-status.txt` හි බලන්න.

## Phone එකෙන් පරීක්ෂා කිරීමට ඉතිරි දේ

1. Cloud Admin account එකේ email/password සමඟ login වෙන්න. Assistant විසින් ඔබේ password එක වෙනස් කර නැහැ.
2. Supervisor කෙනෙක් හදා project එකක් assign කර වෙනත් phone එකකින් access test කරන්න.
3. Android/iPhone වල සැබෑ GPS, receipt upload සහ Home Screen install/launch පරීක්ෂා කරන්න.
4. Google Drive සඳහා OAuth Client ID සහ ඔබේ account consent වෙනම අවශ්‍යයි.

## මේ package එකේ කොටස්

- `deploy/` — GitHub Pages වෙත දැමිය යුතු static phone app එක. Python/Node server අවශ්‍ය නැහැ.
- `backend/phone.sql` — review කළ යුතු additive database/RPC update එක. Owner අනුමැතියෙන් run කර ඇත; නැවත run කරන්න එපා.
- `backend/phone-users.ts` — Supabase Edge Function account management source. Owner අනුමැතියෙන් deploy කර ඇත.
- `backend/rollback.sql` — පවතින assignment helper/permissions routing වෙත ආපසු යාමේ script එක; records මකන්නේ නැහැ.
- `tests/`, `evidence/` — local Postgres, browser සහ mocked account-handler පරීක්ෂණ.
- `rollback/index-before-pwa.html` — කලින් GitHub HTML source copy එක. මෙය deploy folder එකට දාන්න එපා.

දැනට publish කළ code එක භාවිතා කරන්න. වෙනත් වෙනස්කමක් කිරීමට පෙර backup සහ branch review කරන්න.

## Publish කළ පසුව phone එකට දාගන්නේ මෙහෙමයි

**Android:** Chrome එකෙන් app HTTPS link එක open කරන්න → Install button හෝ Chrome menu → Install app / Add to Home Screen.

**iPhone:** Safari එකෙන් එම link එක open කරන්න → Share → Add to Home Screen → Add. අවශ්‍ය නම් Open as Web App option එක තෝරන්න.

එකම link එක Admin සහ Supervisors දෙපාර්ශ්වයටම දෙන්න. Login අනුව අදාළ screens/projects පමණක් ලැබේ. Supervisor account එකේ email සහ තමන්ගේ password භාවිතා කරයි. Public signup එකක් නැහැ. පළමු temporary password එක වෙනස් කළ යුතුයි.

App Store / Play Store fee එකක් ගෙවන්න අවශ්‍ය නැහැ. Existing Supabase organization එක free tier බව පරීක්ෂා කළා. අලුත් paid service එකක්, paid project/branch එකක් හෝ GitHub Actions workflow එකක් සකස් කර/ධාවනය කර නැහැ. Free-tier capacity ඉක්මවූ විට වැඩ නවතින්න/සීමා වෙන්න පුළුවන්; අසීමිත භාවිතයක් පොරොන්දු වෙන්නේ නැහැ.

## GitHub Pages publishing — approval ලැබුණු පසුව

1. පළමුව backend SQL, account-management function සහ security smoke tests අවසන් කරන්න.
2. දැනට ඇති `index.html` copy එක ආරක්ෂිතව තබාගන්න. වෙනම branch එකක changes review කරන්න.
3. ZIP එකේ `deploy` folder එක **ඇතුළේ contents** repository root එකට දාන්න. `deploy` folder එකම දාන්න එපා; `index.html`, `app.js`, `cloud.js`, `config.js`, `style.css`, `sw.js`, `manifest.webmanifest`, icons, `vendor/`, `fonts/` root එක යටතේ තිබිය යුතුයි.
4. Pages URL එකේ `/early-birds/` path එකට app එක නිවැරදිව scope කරලා තියෙනවා. Root `/app.js` වැනි වෙනත් site එකකට යන absolute asset paths භාවිතා කරන්නේ නැහැ.
5. Service worker එක phone shell assets පමණක් cache කරයි. Login responses, database data, receipts හෝ Google responses cache කරන්නේ නැහැ.
6. පරණ HTML localStorage/Firebase data ස්වයංක්‍රීයව cloud එකට මාරු වෙන්නේ නැහැ. දැනට ඇති Supabase cloud records මේ package එකෙන් වෙනස් කර නැහැ. වෙනත් device එකේ තිබෙන පැරණි local data import කිරීමට වෙනම review කළ migration එකක් අවශ්‍යයි.

`config.js` තුළ තිබෙන්නේ public Supabase URL සහ publishable key එක පමණයි. Service-role key, secret key, database password හෝ private Google token GitHub/HTML/chat එකට දාන්න එපා.

## Gateway connection තත්ත්වය

App එක existing schema එක හඳුනාගෙන read/login mode සහ දැනට ආරක්ෂිත RPC ක්‍රියාකාරකම් භාවිතා කළ හැකියි. එවිට "Phone preview" banner එක පෙන්වයි. සම්පූර්ණ handover, account management, reversals, atomic progress changes සහ අලුත් money sends සඳහා reviewed gateway අවශ්‍ය බව පැහැදිලි error එකකින් පෙන්වයි; success ලෙස පෙන්වන්නේ නැහැ.

Existing backend එකේ request approve කිරීමෙන් pending transfer එකක් ස්වයංක්‍රීයව හැදෙනවා. එය ලැබුණු බව Supervisor තහවුරු කළ පසුව පමණක් balance එක වැඩි වෙනවා. එම request එක සඳහා නැවත අලුත් transfer එකක් යවන්න එපා.

## Media, Google Drive සහ exports

Photos private `project-media` storage bucket එකේ තබයි. Signed image links කාලසීමාවක් ඇත. JPG/PNG, file එකකට 3 MB සීමාවක් ඇත. Font සහ SDK app එක සමඟම ඇතුළත් කර ඇති නිසා ඒවා load කිරීමට external CDN එකක් අවශ්‍ය නැහැ.

Settings → Data + photos download මගින් JSON export එකක් ගත හැකියි. Accountsවල password hashes හෝ Supabase Auth sessions එයට ඇතුළත් නොවේ. Signed links සමඟ media bytes ද ඇතුළත් කරයි; total photo export limit 20 MB.

`config.js` හි `googleClientId` සකස් කර Google OAuth consent ලබාදුන් පසුව Drive backup/project export ක්‍රියාත්මක කළ හැකියි. Google Drive folder permissions app permissionsවලින් ස්වයංක්‍රීයව වෙනස් කරන්නේ නැහැ. Project exports තුළ credential hashes නැහැ.

Cloud restore සහ Python-version JSON restore මේ phone app එකේ activate කර නැහැ. Live cloud data අහම්බෙන් replace නොකිරීමට ඒවා block කරයි. Full operational recovery සඳහා existing database/provider backup සහ media backup වෙනම සැලැස්මකින් පරීක්ෂා කළ යුතුයි.

## Offline සහ GPS

Online login කළ page එක තවම විවෘතව තිබියදී bills, daily notes සහ attendance queue කළ හැකියි. Settings → Sync queue භාවිතා කරන්න. Browser data clear කළොත් unsynced queue නැතිවෙයි. Queue එක user ID එකට සීමා කර ඇත.

Offline page reload පසු cached financial state එකක් හෝ offline login එකක් සපයන්නේ නැහැ. Photos/records සඳහා online authorization අවශ්‍යයි. GPS සඳහා HTTPS සහ phone Location permission අවශ්‍යයි. Accuracy 100mට වඩා නරක නම් request reject කරයි. Offline device time/location proof of attendance ලෙස නොසලකයි; Admin review/correction අවශ්‍ය විය හැකියි.

## Developer verification

Package එකේ `deploy/` යටතේ static files ඇත; GitHub source එකේ ඒවා root එකේ ඇත. Runtime එකට Node අවශ්‍ය නැහැ. Tests කිරීමට පමණක් Node 22+:

```sh
npm ci
npm run test:db
npm run test:accounts
npx playwright install chromium
npm run test:browser
```

`tests/schema-fixture.sql` යනු local test bootstrap එකක් පමණයි. එය live database එකක run කරන්න එපා. `VERIFICATION.md` තුළ සත්‍ය test results සහ තවම ඉතිරි පරීක්ෂණ පැහැදිලිව සඳහන්ය.
