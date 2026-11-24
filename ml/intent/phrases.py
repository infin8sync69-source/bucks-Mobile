"""Vocabulary and phrasings for the on-device intent model, per language.

Languages: en, hi (Devanagari), hi-Latn (Hinglish), kn, kn-Latn, ta, te, ml, ml-Latn (Manglish). A template starting with "!" is eval-only: it never
appears in training, so the eval measures sentence patterns the model has not seen. Round 2 (2026-11-17) moved the round-1
eval patterns into training and added fresh eval-only ones. Indian-language phrases still need a native speaker's review.
"""

# ---------- places: canonical English -> surface forms; PLACE_TO holds "to <place>" where the ending depends on the word ----------
PLACES = {
    "MG Road": {"en": ["MG Road", "M G Road"], "hi": ["एमजी रोड"], "hi-Latn": ["MG road", "em jee road"], "kn": ["ಎಂ.ಜಿ. ರಸ್ತೆ", "ಎಂಜಿ ರೋಡ್"], "kn-Latn": ["MG road"], "ta": ["எம்ஜி ரோடு"], "te": ["ఎంజీ రోడ్"]},
    "Koramangala": {"en": ["Koramangala"], "hi": ["कोरमंगला"], "hi-Latn": ["Koramangala"], "kn": ["ಕೋರಮಂಗಲ"], "kn-Latn": ["Koramangala"], "ta": ["கோரமங்களா"], "te": ["కోరమంగళ"]},
    "Indiranagar": {"en": ["Indiranagar", "Indiranagar 100 ft road"], "hi": ["इंदिरानगर"], "hi-Latn": ["Indiranagar"], "kn": ["ಇಂದಿರಾನಗರ"], "kn-Latn": ["Indiranagar"], "ta": ["இந்திராநகர்"], "te": ["ఇందిరానగర్"]},
    "Jayanagar": {"en": ["Jayanagar", "Jayanagar 4th block"], "hi": ["जयनगर"], "hi-Latn": ["Jayanagar"], "kn": ["ಜಯನಗರ"], "kn-Latn": ["Jayanagar"], "ta": ["ஜெயநகர்"], "te": ["జయనగర్"]},
    "Whitefield": {"en": ["Whitefield", "ITPL Whitefield"], "hi": ["व्हाइटफील्ड"], "hi-Latn": ["Whitefield"], "kn": ["ವೈಟ್‌ಫೀಲ್ಡ್"], "kn-Latn": ["Whitefield"], "ta": ["வைட்ஃபீல்ட்"], "te": ["వైట్‌ఫీల్డ్"]},
    "Majestic": {"en": ["Majestic", "Majestic bus stand"], "hi": ["मैजेस्टिक"], "hi-Latn": ["Majestic"], "kn": ["ಮೆಜೆಸ್ಟಿಕ್"], "kn-Latn": ["Majestic"], "ta": ["மெஜஸ்டிக்"], "te": ["మెజెస్టిక్"]},
    "Kempegowda airport": {"en": ["the airport", "Kempegowda airport"], "hi": ["एयरपोर्ट"], "hi-Latn": ["airport"], "kn": ["ವಿಮಾನ ನಿಲ್ದಾಣ", "ಏರ್‌ಪೋರ್ಟ್"], "kn-Latn": ["airport"], "ta": ["விமான நிலையம்", "ஏர்போர்ட்"], "te": ["విమానాశ్రయం", "ఎయిర్‌పోర్ట్"]},
    "Nexus Mall": {"en": ["Nexus Mall"], "hi": ["नेक्सस मॉल"], "hi-Latn": ["Nexus mall"], "kn": ["ನೆಕ್ಸಸ್ ಮಾಲ್"], "kn-Latn": ["Nexus mall"], "ta": ["நெக்ஸஸ் மால்"], "te": ["నెక్సస్ మాల్"]},
    "HSR Layout": {"en": ["HSR Layout", "HSR"], "hi": ["एचएसआर लेआउट"], "hi-Latn": ["HSR layout", "HSR"], "kn": ["ಎಚ್‌ಎಸ್‌ಆರ್ ಲೇಔಟ್"], "kn-Latn": ["HSR layout"], "ta": ["எச்எஸ்ஆர் லேஅவுட்"], "te": ["హెచ్‌ఎస్‌ఆర్ లేఅవుట్"]},
    "Electronic City": {"en": ["Electronic City"], "hi": ["इलेक्ट्रॉनिक सिटी"], "hi-Latn": ["Electronic city"], "kn": ["ಎಲೆಕ್ಟ್ರಾನಿಕ್ ಸಿಟಿ"], "kn-Latn": ["Electronic city"], "ta": ["எலக்ட்ரானிக் சிட்டி"], "te": ["ఎలక్ట్రానిక్ సిటీ"]},
    "Marathahalli": {"en": ["Marathahalli"], "hi": ["मराठहल्ली"], "hi-Latn": ["Marathahalli"], "kn": ["ಮಾರತ್ತಹಳ್ಳಿ"], "kn-Latn": ["Marathahalli"], "ta": ["மாரத்தஹள்ளி"], "te": ["మారతహళ్ళి"]},
    "Hebbal": {"en": ["Hebbal"], "hi": ["हेब्बाल"], "hi-Latn": ["Hebbal"], "kn": ["ಹೆಬ್ಬಾಳ"], "kn-Latn": ["Hebbal"], "ta": ["ஹெப்பால்"], "te": ["హెబ్బాల్"]},
    "Banashankari": {"en": ["Banashankari"], "hi": ["बनशंकरी"], "hi-Latn": ["Banashankari"], "kn": ["ಬನಶಂಕರಿ"], "kn-Latn": ["Banashankari"], "ta": ["பனசங்கரி"], "te": ["బనశంకరి"]},
}
PLACE_TO = {
    "MG Road": {"kn": ["ಎಂ.ಜಿ. ರಸ್ತೆಗೆ", "ಎಂಜಿ ರೋಡ್‌ಗೆ"], "kn-Latn": ["MG roadge"], "ta": ["எம்ஜி ரோடுக்கு"], "te": ["ఎంజీ రోడ్‌కి"]},
    "Koramangala": {"kn": ["ಕೋರಮಂಗಲಕ್ಕೆ"], "kn-Latn": ["Koramangalakke"], "ta": ["கோரமங்களாவுக்கு"], "te": ["కోరమంగళకి"]},
    "Indiranagar": {"kn": ["ಇಂದಿರಾನಗರಕ್ಕೆ"], "kn-Latn": ["Indiranagarakke"], "ta": ["இந்திராநகருக்கு"], "te": ["ఇందిరానగర్‌కి"]},
    "Jayanagar": {"kn": ["ಜಯನಗರಕ್ಕೆ"], "kn-Latn": ["Jayanagarakke"], "ta": ["ஜெயநகருக்கு"], "te": ["జయనగర్‌కి"]},
    "Whitefield": {"kn": ["ವೈಟ್‌ಫೀಲ್ಡ್‌ಗೆ"], "kn-Latn": ["Whitefieldge"], "ta": ["வைட்ஃபீல்டுக்கு"], "te": ["వైట్‌ఫీల్డ్‌కి"]},
    "Majestic": {"kn": ["ಮೆಜೆಸ್ಟಿಕ್‌ಗೆ"], "kn-Latn": ["Majesticge"], "ta": ["மெஜஸ்டிக்குக்கு"], "te": ["మెజెస్టిక్‌కి"]},
    "Kempegowda airport": {"kn": ["ವಿಮಾನ ನಿಲ್ದಾಣಕ್ಕೆ", "ಏರ್‌ಪೋರ್ಟ್‌ಗೆ"], "kn-Latn": ["airportge"], "ta": ["விமான நிலையத்துக்கு", "ஏர்போர்ட்டுக்கு"], "te": ["విమానాశ్రయానికి", "ఎయిర్‌పోర్ట్‌కి"]},
    "Nexus Mall": {"kn": ["ನೆಕ್ಸಸ್ ಮಾಲ್‌ಗೆ"], "kn-Latn": ["Nexus mallge"], "ta": ["நெக்ஸஸ் மாலுக்கு"], "te": ["నెక్సస్ మాల్‌కి"]},
    "HSR Layout": {"kn": ["ಎಚ್‌ಎಸ್‌ಆರ್ ಲೇಔಟ್‌ಗೆ"], "kn-Latn": ["HSR layoutge"], "ta": ["எச்எஸ்ஆர் லேஅவுட்டுக்கு"], "te": ["హెచ్‌ఎస్‌ఆర్ లేఅవుట్‌కి"]},
    "Electronic City": {"kn": ["ಎಲೆಕ್ಟ್ರಾನಿಕ್ ಸಿಟಿಗೆ"], "kn-Latn": ["Electronic cityge"], "ta": ["எலக்ட்ரானிக் சிட்டிக்கு"], "te": ["ఎలక్ట్రానిక్ సిటీకి"]},
    "Marathahalli": {"kn": ["ಮಾರತ್ತಹಳ್ಳಿಗೆ"], "kn-Latn": ["Marathahallige"], "ta": ["மாரத்தஹள்ளிக்கு"], "te": ["మారతహళ్ళికి"]},
    "Hebbal": {"kn": ["ಹೆಬ್ಬಾಳಕ್ಕೆ"], "kn-Latn": ["Hebbalakke"], "ta": ["ஹெப்பாலுக்கு"], "te": ["హెబ్బాల్‌కి"]},
    "Banashankari": {"kn": ["ಬನಶಂಕರಿಗೆ"], "kn-Latn": ["Banashankarige"], "ta": ["பனசங்கரிக்கு"], "te": ["బనశంకరికి"]},
}
VEHICLES = {
    "AUTO": {"en": ["auto", "rickshaw", "auto rickshaw"], "hi": ["ऑटो", "रिक्शा"], "hi-Latn": ["auto", "rickshaw"], "kn": ["ಆಟೋ"], "kn-Latn": ["auto"], "ta": ["ஆட்டோ"], "te": ["ఆటో"]},
    "CAB": {"en": ["cab", "taxi", "car"], "hi": ["कैब", "टैक्सी"], "hi-Latn": ["cab", "taxi", "gaadi"], "kn": ["ಕ್ಯಾಬ್", "ಟ್ಯಾಕ್ಸಿ"], "kn-Latn": ["cab", "taxi"], "ta": ["கேப்", "டாக்ஸி"], "te": ["క్యాబ్", "టాక్సీ"]},
    "BIKE": {"en": ["bike", "bike taxi", "scooter"], "hi": ["बाइक"], "hi-Latn": ["bike"], "kn": ["ಬೈಕ್"], "kn-Latn": ["bike"], "ta": ["பைக்"], "te": ["బైక్"]},
}
ITEMS = {
    "sugar": {"en": ["sugar"], "hi": ["चीनी"], "hi-Latn": ["cheeni", "chini"], "kn": ["ಸಕ್ಕರೆ"], "kn-Latn": ["sakkare"], "ta": ["சர்க்கரை"], "te": ["చక్కెర"]},
    "milk": {"en": ["milk"], "hi": ["दूध"], "hi-Latn": ["doodh", "dudh"], "kn": ["ಹಾಲು"], "kn-Latn": ["haalu"], "ta": ["பால்"], "te": ["పాలు"]},
    "eggs": {"en": ["eggs"], "hi": ["अंडे"], "hi-Latn": ["ande", "anda"], "kn": ["ಮೊಟ್ಟೆ"], "kn-Latn": ["motte"], "ta": ["முட்டை"], "te": ["గుడ్లు"]},
    "rice": {"en": ["rice"], "hi": ["चावल"], "hi-Latn": ["chawal"], "kn": ["ಅಕ್ಕಿ"], "kn-Latn": ["akki"], "ta": ["அரிசி"], "te": ["బియ్యం"]},
    "wheat flour": {"en": ["atta", "wheat flour"], "hi": ["आटा"], "hi-Latn": ["atta", "aata"], "kn": ["ಗೋಧಿ ಹಿಟ್ಟು"], "kn-Latn": ["godhi hittu"], "ta": ["கோதுமை மாவு"], "te": ["గోధుమ పిండి"]},
    "vegetables": {"en": ["vegetables", "veggies"], "hi": ["सब्ज़ी"], "hi-Latn": ["sabzi", "sabji"], "kn": ["ತರಕಾರಿ"], "kn-Latn": ["tarakari"], "ta": ["காய்கறி"], "te": ["కూరగాయలు"]},
    "tomatoes": {"en": ["tomatoes"], "hi": ["टमाटर"], "hi-Latn": ["tamatar"], "kn": ["ಟೊಮೆಟೊ"], "kn-Latn": ["tomato"], "ta": ["தக்காளி"], "te": ["టమాటాలు"]},
    "onions": {"en": ["onions"], "hi": ["प्याज़"], "hi-Latn": ["pyaaz", "kanda"], "kn": ["ಈರುಳ್ಳಿ"], "kn-Latn": ["eerulli"], "ta": ["வெங்காயம்"], "te": ["ఉల్లిపాయలు"]},
    "cooking oil": {"en": ["cooking oil", "oil"], "hi": ["तेल"], "hi-Latn": ["tel"], "kn": ["ಎಣ್ಣೆ"], "kn-Latn": ["enne"], "ta": ["எண்ணெய்"], "te": ["నూనె"]},
    "curd": {"en": ["curd"], "hi": ["दही"], "hi-Latn": ["dahi"], "kn": ["ಮೊಸರು"], "kn-Latn": ["mosaru"], "ta": ["தயிர்"], "te": ["పెరుగు"]},
    "paneer": {"en": ["paneer"], "hi": ["पनीर"], "hi-Latn": ["paneer"], "kn": ["ಪನೀರ್"], "kn-Latn": ["paneer"], "ta": ["பனீர்"], "te": ["పనీర్"]},
    "chicken": {"en": ["chicken"], "hi": ["चिकन"], "hi-Latn": ["chicken", "murga"], "kn": ["ಚಿಕನ್", "ಕೋಳಿ ಮಾಂಸ"], "kn-Latn": ["chicken"], "ta": ["சிக்கன்"], "te": ["చికెన్"]},
    "bread": {"en": ["bread"], "hi": ["ब्रेड"], "hi-Latn": ["bread"], "kn": ["ಬ್ರೆಡ್"], "kn-Latn": ["bread"], "ta": ["ரொட்டி"], "te": ["బ్రెడ్"]},
    "biryani": {"en": ["biryani", "biriyani"], "hi": ["बिरयानी"], "hi-Latn": ["biryani"], "kn": ["ಬಿರಿಯಾನಿ"], "kn-Latn": ["biryani"], "ta": ["பிரியாணி"], "te": ["బిర్యానీ"]},
    "pharmacy": {"en": ["a pharmacy", "a medical shop", "medicines"], "hi": ["दवाई की दुकान"], "hi-Latn": ["medical store", "dawai ki dukaan"], "kn": ["ಮೆಡಿಕಲ್ ಶಾಪ್"], "kn-Latn": ["medical shop"], "ta": ["மருந்துக் கடை"], "te": ["మెడికల్ షాప్"]},
    "plumber": {"en": ["a plumber", "plumber"], "hi": ["प्लंबर"], "hi-Latn": ["plumber"], "kn": ["ಪ್ಲಂಬರ್"], "kn-Latn": ["plumber"], "ta": ["பிளம்பர்"], "te": ["ప్లంబర్"]},
    "electrician": {"en": ["an electrician", "electrician"], "hi": ["बिजली वाला", "इलेक्ट्रीशियन"], "hi-Latn": ["bijli wala", "electrician"], "kn": ["ಎಲೆಕ್ಟ್ರಿಷಿಯನ್"], "kn-Latn": ["electrician"], "ta": ["எலக்ட்ரீஷியன்"], "te": ["ఎలక్ట్రీషియన్"]},
    "tailor": {"en": ["a tailor", "tailor"], "hi": ["दर्ज़ी"], "hi-Latn": ["darzi", "tailor"], "kn": ["ಟೈಲರ್"], "kn-Latn": ["tailor"], "ta": ["தையல்காரர்"], "te": ["దర్జీ"]},
    "doctor": {"en": ["a doctor", "doctor"], "hi": ["डॉक्टर"], "hi-Latn": ["doctor"], "kn": ["ವೈದ್ಯರು", "ಡಾಕ್ಟರ್"], "kn-Latn": ["doctor"], "ta": ["டாக்டர்"], "te": ["డాక్టర్"]},
    "carpenter": {"en": ["a carpenter", "carpenter"], "hi": ["बढ़ई"], "hi-Latn": ["badhai", "carpenter"], "kn": ["ಬಡಗಿ"], "kn-Latn": ["badagi", "carpenter"], "ta": ["தச்சர்"], "te": ["వడ్రంగి"]},
    "cook": {"en": ["a cook", "cook"], "hi": ["खाना बनाने वाली"], "hi-Latn": ["cook", "khana banane wali"], "kn": ["ಅಡುಗೆಯವರು"], "kn-Latn": ["cook"], "ta": ["சமையல்காரர்"], "te": ["వంటమనిషి"]},
    "mechanic": {"en": ["a mechanic", "mechanic"], "hi": ["मैकेनिक"], "hi-Latn": ["mechanic", "mistri"], "kn": ["ಮೆಕ್ಯಾನಿಕ್"], "kn-Latn": ["mechanic"], "ta": ["மெக்கானிக்"], "te": ["మెకానిక్"]},
    "house cleaning": {"en": ["house cleaning", "a maid", "cleaning help"], "hi": ["घर की सफ़ाई वाली"], "hi-Latn": ["safai wali", "kaam wali bai"], "kn": ["ಮನೆ ಕೆಲಸದವರು"], "kn-Latn": ["mane kelasadavaru"], "ta": ["வீட்டு வேலைக்காரர்"], "te": ["ఇంటి పనిమనిషి"]},
    "AC repair": {"en": ["AC repair", "an AC mechanic"], "hi": ["एसी रिपेयर"], "hi-Latn": ["AC repair", "AC wala"], "kn": ["ಎಸಿ ರಿಪೇರಿ"], "kn-Latn": ["AC repair"], "ta": ["ஏசி ரிப்பேர்"], "te": ["ఏసీ రిపేర్"]},
    "painter": {"en": ["a painter", "painter"], "hi": ["पेंटर"], "hi-Latn": ["painter"], "kn": ["ಪೇಂಟರ್"], "kn-Latn": ["painter"], "ta": ["பெயிண்டர்"], "te": ["పెయింటర్"]},
}
SORTS = {
    "PRICE": {"en": ["sort by price", "show the cheapest first", "sort by lowest price", "cheapest on top", "price low to high", "!order by price"],
              "hi": ["कीमत के हिसाब से दिखाओ", "सस्ते वाले पहले दिखाओ", "!दाम के हिसाब से लगाओ"], "hi-Latn": ["price se sort karo", "saste wale pehle dikhao", "kam daam wale pehle", "!sasta pehle"],
              "kn": ["ಬೆಲೆ ಪ್ರಕಾರ ತೋರಿಸಿ", "ಕಡಿಮೆ ಬೆಲೆ ಮೊದಲು", "!ಅಗ್ಗದವು ಮೊದಲು"], "kn-Latn": ["bele prakara thorisi", "kammi bele modalu", "!cheap modalu"],
              "ta": ["விலைப்படி வரிசைப்படுத்து", "குறைந்த விலை முதலில்", "!மலிவானது முதலில்"], "te": ["ధర ప్రకారం చూపించు", "తక్కువ ధర ముందు", "!చౌకవి ముందు"]},
    "NEAR": {"en": ["sort by distance", "nearest first", "sort by nearest", "closest first", "show the nearest ones", "!what's closest to me"],
             "hi": ["पास वाले पहले दिखाओ", "नज़दीक वाले पहले", "!सबसे पास वाले दिखाओ"], "hi-Latn": ["paas wale pehle dikhao", "nazdeek wale pehle", "!sabse paas wala"],
             "kn": ["ಹತ್ತಿರದವು ಮೊದಲು ತೋರಿಸಿ", "ಹತ್ತಿರ ಇರುವುದು ಮೊದಲು", "!ತುಂಬಾ ಹತ್ತಿರದವು"], "kn-Latn": ["hathra iruvudu modalu thorisi", "hathra iruvudu modalu", "!tumba hathra"],
             "ta": ["அருகில் உள்ளவை முதலில் காட்டு", "பக்கத்தில் உள்ளது முதலில்", "!மிக அருகில்"], "te": ["దగ్గరవి ముందు చూపించు", "దగ్గర ఉన్నవి ముందు", "!చాలా దగ్గరవి"]},
    "TRUST": {"en": ["sort by trust", "most recommended first", "sort by rating", "best rated first", "!most trusted on top"],
              "hi": ["सबसे भरोसेमंद पहले दिखाओ", "अच्छी रेटिंग वाले पहले", "!भरोसेमंद वाले ऊपर"], "hi-Latn": ["sabse trusted pehle dikhao", "rating se sort karo", "!sabse bharosemand pehle"],
              "kn": ["ಹೆಚ್ಚು ಶಿಫಾರಸು ಮಾಡಿದವು ಮೊದಲು", "ರೇಟಿಂಗ್ ಪ್ರಕಾರ ತೋರಿಸಿ", "!ನಂಬಿಕೆಯವು ಮೊದಲು"], "kn-Latn": ["most recommended modalu", "rating prakara thorisi", "!trusted modalu"],
              "ta": ["அதிகம் பரிந்துரைக்கப்பட்டவை முதலில்", "ரேட்டிங் படி காட்டு", "!நம்பகமானவை முதலில்"], "te": ["ఎక్కువ సిఫార్సు చేసినవి ముందు", "రేటింగ్ ప్రకారం చూపించు", "!నమ్మకమైనవి ముందు"]},
}

# ---------- templates; {v} vehicle, {p} place, {pt} "to <place>", {i} item ----------
RIDE = {
    "en": ["{v} to {p}", "book an {v} to {p}", "book a {v} to {p}", "I need a {v} to {p}", "get me a {v} to {p}", "{v} for {p}", "call a {v} to go to {p}",
           "I want a {v} to {p}", "send a {v}, I'm going to {p}", "need {v} to {p} now", "can you book me a {v} to {p}", "{p} by {v}", "take me to {p} in a {v}",
           "can you call a {v}, going to {p}", "{v} for {p} now", "!{v} please, going to {p}", "!arrange a {v} to {p}", "!I have to reach {p}, get a {v}"],
    "hi": ["{p} के लिए {v} चाहिए", "{p} तक {v} बुक करो", "मुझे {p} जाना है, {v} बुलाओ", "{p} जाने के लिए {v} चाहिए", "{v} बुक करो {p} के लिए", "{v} से {p} जाना है",
           "!जल्दी से {p} के लिए {v} भेजो", "!{p} पहुँचना है, {v} कर दो"],
    "hi-Latn": ["{p} ke liye {v} chahiye", "{p} tak {v} book karo", "mujhe {p} jaana hai {v} bulao", "{v} chahiye {p} jaane ke liye", "{p} jaana hai {v} se",
                "{v} book karo {p} ke liye", "{p} chalna hai {v} mein", "bhaiya {p} ke liye {v} bhejo", "{p} jana hai {v} karo",
                "!jaldi {p} ke liye {v} bulao", "!{v} se {p} chhod do", "!{p} pahunchna hai {v} chahiye"],
    "kn": ["{pt} {v} ಬೇಕು", "{pt} {v} ಬುಕ್ ಮಾಡಿ", "ನಾನು {pt} ಹೋಗಬೇಕು, {v} ಕರೆಯಿರಿ", "{pt} ಹೋಗಲು {v} ಬೇಕು", "{pt} ಒಂದು {v} ಕಳಿಸಿ",
           "!ಬೇಗ {pt} ಒಂದು {v} ಬೇಕು", "!{pt} ಹೋಗಬೇಕು, {v} ಬುಕ್ ಮಾಡಿ"],
    "kn-Latn": ["{pt} {v} beku", "{pt} {v} book maadi", "{pt} hogbeku {v} kodi", "{pt} hogoke {v} beku", "{pt} ondu {v} kalsi",
                "!bega {pt} {v} beku", "!{pt} hogbeku {v} book maadi"],
    "ta": ["{pt} {v} வேண்டும்", "{pt} {v} புக் பண்ணுங்க", "நான் {pt} போகணும், {v} கூப்பிடுங்க", "{pt} போக {v} வேணும்", "{pt} ஒரு {v} அனுப்புங்க",
           "!சீக்கிரம் {pt} ஒரு {v} வேணும்", "!{pt} போகணும், {v} புக் பண்ணுங்க"],
    "te": ["{pt} {v} కావాలి", "{pt} {v} బుక్ చేయండి", "నేను {pt} వెళ్ళాలి, {v} పిలవండి", "{pt} వెళ్ళడానికి {v} కావాలి", "{pt} ఒక {v} పంపండి",
           "!తొందరగా {pt} ఒక {v} కావాలి", "!{pt} వెళ్ళాలి, {v} బుక్ చేయండి"],
}
RIDE_NO_VEHICLE = {  # no vehicle named -> AUTO
    "en": ["take me to {p}", "drop me at {p}", "I want to go to {p}", "I need to go to {p}", "get me to {p}", "ride to {p}", "!going to {p}", "!I have to reach {p}"],
    "hi": ["मुझे {p} ले चलो", "मुझे {p} जाना है", "{p} छोड़ दो", "!{p} पहुँचा दो"],
    "hi-Latn": ["mujhe {p} le chalo", "{p} jaana hai", "{p} jana hai", "mujhe {p} chhod do", "{p} tak chhod do", "!{p} pahuncha do", "!{p} chalo"],
    "kn": ["ನನ್ನನ್ನು {pt} ಕರೆದುಕೊಂಡು ಹೋಗಿ", "ನಾನು {pt} ಹೋಗಬೇಕು", "!{pt} ತಲುಪಿಸಿ"],
    "kn-Latn": ["{pt} hogbeku", "{pt} karkondu hogi", "!{pt} talupisi"],
    "ta": ["என்னை {pt} கூட்டிட்டு போங்க", "நான் {pt} போகணும்", "!{pt} கொண்டு விடுங்க"],
    "te": ["నన్ను {pt} తీసుకెళ్ళండి", "నేను {pt} వెళ్ళాలి", "!{pt} చేర్చండి"],
}
RIDE_NO_PLACE = {
    "en": ["I need a {v}", "book a {v}", "get me a {v}", "call a {v}", "{v} please", "!send a {v} here", "!I want a {v} now"],
    "hi": ["{v} चाहिए", "{v} बुलाओ", "!एक {v} भेजो"],
    "hi-Latn": ["{v} chahiye", "{v} bulao", "ek {v} bhejo", "!{v} mangwao", "!jaldi {v} chahiye"],
    "kn": ["{v} ಬೇಕು", "ಒಂದು {v} ಕರೆಯಿರಿ", "!ಒಂದು {v} ಕಳಿಸಿ"],
    "kn-Latn": ["{v} beku", "ondu {v} kalsi", "!{v} kareyiri"],
    "ta": ["{v} வேண்டும்", "ஒரு {v} கூப்பிடுங்க", "!ஒரு {v} அனுப்புங்க"],
    "te": ["{v} కావాలి", "ఒక {v} పిలవండి", "!ఒక {v} పంపండి"],
}
SEARCH = {
    "en": ["find {i}", "{i} near me", "where can I get {i}", "order {i}", "I need {i}", "looking for {i} nearby", "any {i} around here", "I want {i}", "get me {i}",
           "{i} nearby", "search for {i}", "show me {i}", "who sells {i}", "!where do I find {i}", "!I'm looking for {i}", "!need some {i}"],
    "hi": ["मुझे {i} चाहिए", "{i} कहाँ मिलेगा", "पास में {i} कहाँ है", "{i} मंगवाना है", "{i} ढूंढो", "!आसपास {i} मिलेगा क्या", "!{i} दिखाओ"],
    "hi-Latn": ["mujhe {i} chahiye", "{i} kahan milega", "paas mein {i}", "{i} order karna hai", "{i} mangwana hai", "{i} dhundo", "{i} chahiye", "{i} kidhar milega",
                "aas paas {i} hai kya", "!{i} dikhao", "!{i} kaha milta hai", "!koi {i} hai paas mein"],
    "kn": ["{i} ಬೇಕು", "ಹತ್ತಿರ {i} ಎಲ್ಲಿ ಸಿಗುತ್ತೆ", "{i} ಎಲ್ಲಿ ಸಿಗುತ್ತೆ", "{i} ಹುಡುಕಿ", "ನನಗೆ {i} ಬೇಕು", "!ಹತ್ತಿರದಲ್ಲಿ {i} ಇದೆಯಾ", "!{i} ತೋರಿಸಿ"],
    "kn-Latn": ["{i} beku", "hathra {i} elli sigutte", "{i} elli sigutte", "{i} hudki", "nange {i} beku", "!hathradalli {i} ideya", "!{i} thorisi"],
    "ta": ["{i} வேண்டும்", "அருகில் {i} எங்கே கிடைக்கும்", "{i} எங்கே கிடைக்கும்", "{i} தேடு", "எனக்கு {i} வேண்டும்", "!பக்கத்தில் {i} இருக்கா", "!{i} காட்டு"],
    "te": ["{i} కావాలి", "దగ్గరలో {i} ఎక్కడ దొరుకుతుంది", "{i} ఎక్కడ దొరుకుతుంది", "{i} వెతకండి", "నాకు {i} కావాలి", "!దగ్గరలో {i} ఉందా", "!{i} చూపించు"],
}
COMPARE = {
    "en": ["compare {i}", "cheapest {i}", "which {i} is best", "best {i} near me", "best {i}", "top rated {i}", "who has the cheapest {i}", "compare prices for {i}",
           "!which {i} should I choose", "!lowest price {i}", "!most recommended {i}"],
    "hi": ["सबसे सस्ता {i}", "{i} की तुलना करो", "सबसे अच्छा {i} कौन सा है", "!सबसे बढ़िया {i} बताओ"],
    "hi-Latn": ["sabse sasta {i}", "{i} compare karo", "sabse accha {i} kaunsa hai", "best {i} batao", "sasta {i} kahan hai", "!sabse badhiya {i}", "!kaunsa {i} accha hai",
                "!{i} ka rate compare karo"],
    "kn": ["ಅಗ್ಗದ {i} ಯಾವುದು", "{i} ಹೋಲಿಸಿ", "ಒಳ್ಳೆಯ {i} ಯಾವುದು", "!ಅತ್ಯುತ್ತಮ {i} ಯಾವುದು", "!{i} ಬೆಲೆ ಹೋಲಿಸಿ"],
    "kn-Latn": ["cheap {i} yavudu", "best {i} yavudu", "{i} compare maadi", "olle {i} yavudu", "!kammi bele {i}", "!yav {i} chennagide"],
    "ta": ["மலிவான {i} எது", "{i} ஒப்பிடு", "சிறந்த {i} எது", "!நல்ல {i} எது", "!{i} விலை ஒப்பிடு"],
    "te": ["చౌకైన {i} ఏది", "{i} పోల్చండి", "మంచి {i} ఏది", "!ఉత్తమ {i} ఏది", "!{i} ధరలు పోల్చండి"],
}
POST = {
    "en": ["post a request for {i}", "ask the neighbourhood for {i}", "nobody has {i}, post a request", "ask people nearby for {i}", "!put up a request for {i}",
           "!can you ask around for {i}"],
    "hi": ["{i} के लिए रिक्वेस्ट पोस्ट करो", "!पड़ोस में {i} के लिए पूछो"],
    "hi-Latn": ["{i} ke liye request post karo", "{i} ke liye post daalo", "logon se {i} ke liye pucho", "!padosiyon se {i} pucho", "!{i} ki request daal do"],
    "kn": ["{i} ಬೇಕು ಅಂತ ವಿನಂತಿ ಪೋಸ್ಟ್ ಮಾಡಿ", "!ಅಕ್ಕಪಕ್ಕದವರಿಗೆ {i} ಬಗ್ಗೆ ಕೇಳಿ"],
    "kn-Latn": ["{i} beku antha request post maadi", "!{i} bagge request haaki"],
    "ta": ["{i} வேண்டும் என்று கோரிக்கை போடு", "!அக்கம்பக்கத்தில் {i} கேளு"],
    "te": ["{i} కోసం అభ్యర్థన పోస్ట్ చేయండి", "!చుట్టుపక్కల వాళ్ళని {i} గురించి అడగండి"],
}
FIXED = {
    "show_activity": {"en": ["show my orders", "my rides", "order history", "show my activity", "what did I order", "my bookings", "where is my order", "track my order",
                             "!my past trips", "!show my requests"],
                      "hi": ["मेरे ऑर्डर दिखाओ", "मेरी राइड दिखाओ", "!मेरा ऑर्डर कहाँ है"], "hi-Latn": ["mere orders dikhao", "meri rides dikhao", "mera order history",
                      "mera order kahan hai", "!meri bookings dikhao", "!pichle orders"], "kn": ["ನನ್ನ ಆರ್ಡರ್‌ಗಳನ್ನು ತೋರಿಸಿ", "ನನ್ನ ಆರ್ಡರ್ ಎಲ್ಲಿದೆ", "!ನನ್ನ ಪ್ರಯಾಣಗಳು"],
                      "kn-Latn": ["nanna orders thorisi", "nanna order ellide", "!nanna rides"], "ta": ["என் ஆர்டர்களைக் காட்டு", "என் ஆர்டர் எங்கே", "!என் பயணங்கள்"],
                      "te": ["నా ఆర్డర్లు చూపించు", "నా ఆర్డర్ ఎక్కడ ఉంది", "!నా ప్రయాణాలు"]},
    "go_online": {"en": ["go online", "start duty", "I'm online", "put me online", "start taking rides", "I'm ready for rides", "!switch me online", "!start my shift"],
                  "hi": ["मुझे ऑनलाइन करो", "ड्यूटी शुरू करो", "!मैं तैयार हूँ, ऑनलाइन करो"], "hi-Latn": ["mujhe online karo", "duty shuru karo", "online kar do",
                  "!duty on karo", "!main ready hoon online karo"], "kn": ["ನನ್ನನ್ನು ಆನ್‌ಲೈನ್ ಮಾಡಿ", "ಡ್ಯೂಟಿ ಶುರು ಮಾಡಿ", "!ಆನ್‌ಲೈನ್ ಹೋಗಬೇಕು"],
                  "kn-Latn": ["duty start maadi", "online maadi", "!online hogbeku"], "ta": ["என்னை ஆன்லைன் ஆக்கு", "டியூட்டி ஆரம்பி", "!ஆன்லைன் போகணும்"],
                  "te": ["నన్ను ఆన్‌లైన్ చేయండి", "డ్యూటీ మొదలుపెట్టు", "!ఆన్‌లైన్ కావాలి"]},
    "become_provider": {"en": ["I want to become a provider", "add my shop", "list my skill", "how do I earn on Bucks", "register my vehicle", "I want to sell on Bucks",
                               "open a shop", "!add my business", "!I want to offer my services"],
                        "hi": ["मुझे अपनी दुकान जोड़नी है", "मुझे अपनी सर्विस लिस्ट करनी है", "!मुझे बेचना है"], "hi-Latn": ["apni dukaan add karni hai", "mujhe kamana hai bucks pe",
                        "apni gaadi register karni hai", "!mujhe apna kaam list karna hai", "!dukaan kholni hai"],
                        "kn": ["ನನ್ನ ಅಂಗಡಿ ಸೇರಿಸಬೇಕು", "ನನ್ನ ವಾಹನ ನೋಂದಣಿ ಮಾಡಬೇಕು", "!ನಾನು ಮಾರಾಟ ಮಾಡಬೇಕು"], "kn-Latn": ["nanna angadi add maadbeku",
                        "nanna gaadi register maadbeku", "!nanu sell maadbeku"], "ta": ["என் கடையைச் சேர்க்க வேண்டும்", "என் வண்டியை பதிவு செய்ய வேண்டும்", "!நான் விற்க வேண்டும்"],
                        "te": ["నా దుకాణం జోడించాలి", "నా వాహనం నమోదు చేయాలి", "!నేను అమ్మాలి"]},
    "confirm_pending": {"en": ["yes", "confirm", "go ahead", "book it", "yes, ring them", "ok", "okay", "sure", "yes please", "do it", "!sure, do it", "!yep, book that",
                               "!sounds good"], "hi": ["हाँ", "ठीक है, बुक करो", "हाँ जी", "!बिल्कुल"], "hi-Latn": ["haan", "haan book karo", "theek hai", "haan ji",
                               "ok kar do", "!haan bhai", "!chalega"], "kn": ["ಹೌದು", "ಸರಿ", "ಆಯ್ತು", "!ಮಾಡಿ"], "kn-Latn": ["houdu", "sari", "aaytu", "!maadi"],
                        "ta": ["ஆமாம்", "சரி", "ஓகே", "!பண்ணுங்க"], "te": ["అవును", "సరే", "ఓకే", "!చేయండి"]},
    "cancel_pending": {"en": ["no", "cancel", "stop", "never mind", "don't book it", "no thanks", "cancel it", "!forget it", "!not now"],
                       "hi": ["नहीं", "रद्द करो", "रहने दो", "!मत करो"], "hi-Latn": ["nahi", "cancel karo", "rehne do", "mat karo", "!nahi chahiye", "!chhodo"],
                       "kn": ["ಬೇಡ", "ರದ್ದು ಮಾಡಿ", "!ಬೇಡ ಬಿಡಿ"], "kn-Latn": ["beda", "cancel maadi", "!beda bidi"], "ta": ["வேண்டாம்", "ரத்து செய்", "!விடுங்க"],
                       "te": ["వద్దు", "రద్దు చేయండి", "!వదిలేయండి"]},
    "show_map": {"en": ["show the map", "open the map", "show me on the map", "map please", "!where am I on the map"], "hi": ["नक्शा दिखाओ", "!मैप खोलो"],
                 "hi-Latn": ["map dikhao", "map kholo", "!naksha dikhao"], "kn": ["ನಕ್ಷೆ ತೋರಿಸಿ", "!ಮ್ಯಾಪ್ ತೆರೆಯಿರಿ"], "kn-Latn": ["map thorisi", "!map open maadi"],
                 "ta": ["வரைபடத்தைக் காட்டு", "!மேப் திற"], "te": ["మ్యాప్ చూపించు", "!మ్యాప్ తెరవండి"]},
    "help": {"en": ["hello", "what's the weather today", "tell me a joke", "who made you", "what can you do", "hi there", "thanks", "how are you", "what time is it",
                    "!good morning", "!who are you", "!thank you so much"], "hi": ["नमस्ते", "आज मौसम कैसा है", "धन्यवाद", "!तुम कौन हो"],
             "hi-Latn": ["kaise ho", "aaj mausam kaisa hai", "tum kya kar sakte ho", "shukriya", "!kya haal hai", "!tum kaun ho"],
             "kn": ["ನಮಸ್ಕಾರ", "ಇವತ್ತು ಹವಾಮಾನ ಹೇಗಿದೆ", "ಧನ್ಯವಾದ", "!ನೀವು ಯಾರು"], "kn-Latn": ["hegiddira", "neenu enu maadtiya", "thanks", "!yaaru neenu"],
             "ta": ["வணக்கம்", "இன்று வானிலை எப்படி", "நன்றி", "!நீங்கள் யார்"], "te": ["నమస్కారం", "ఈరోజు వాతావరణం ఎలా ఉంది", "ధన్యవాదాలు", "!మీరు ఎవరు"]},
}

# ---------- find_content: posts, videos, photos, files and people (explore(p_kind, q) and search_people on the backend) ----------
# The query is copied from the user's words as said (post text and names are matched as written), not translated.
TOPICS = {
    "en": ["cooking", "cricket", "music", "dance", "Coorg coffee", "wedding", "festival", "travel", "comedy", "gardening"],
    "hi": ["खाना", "क्रिकेट", "संगीत", "डांस", "शादी", "त्योहार"],
    "hi-Latn": ["cooking", "cricket", "gaana", "dance", "shaadi", "tyohar"],
    "kn": ["ಅಡುಗೆ", "ಕ್ರಿಕೆಟ್", "ಸಂಗೀತ", "ನೃತ್ಯ", "ಮದುವೆ", "ಹಬ್ಬ", "ಕೊಡಗು ಕಾಫಿ"],
    "kn-Latn": ["aduge", "cricket", "sangeetha", "dance", "maduve", "habba", "Coorg coffee"],
    "ta": ["சமையல்", "கிரிக்கெட்", "இசை", "நடனம்", "திருமணம்", "திருவிழா"],
    "te": ["వంట", "క్రికెట్", "సంగీతం", "డ్యాన్స్", "పెళ్లి", "పండుగ"],
}
NAMES = {
    "en": ["Ravi", "Asha", "Suresh", "Meera", "Kavya", "Arjun", "Priya"],
    "hi": ["रवि", "आशा", "सुरेश", "मीरा", "कविता", "अर्जुन"],
    "hi-Latn": ["Ravi", "Asha", "Suresh", "Meera", "Kavita", "Arjun"],
    "kn": ["ರವಿ", "ಆಶಾ", "ಸುರೇಶ್", "ಮೀರಾ", "ಕಾವ್ಯ", "ಅರ್ಜುನ್"],
    "kn-Latn": ["Ravi", "Asha", "Suresh", "Meera", "Kavya", "Arjun"],
    "ta": ["ரவி", "ஆஷா", "சுரேஷ்", "மீரா", "காவ்யா", "அர்ஜுன்"],
    "te": ["రవి", "ఆశా", "సురేష్", "మీరా", "కావ్య", "అర్జున్"],
}
# kind -> lang -> templates with {t} (topic, which becomes the query)
CONTENT = {
    "VIDEO": {
        "en": ["{t} videos", "show me {t} videos", "find videos about {t}", "any videos of {t}", "watch {t} videos", "!play some {t} videos", "!videos on {t}"],
        "hi": ["{t} के वीडियो दिखाओ", "{t} वीडियो", "{t} के वीडियो ढूंढो", "!{t} पर कोई वीडियो है क्या"],
        "hi-Latn": ["{t} ke videos dikhao", "{t} video", "{t} ki video dhundo", "koi {t} video hai kya", "!{t} wale videos chahiye"],
        "kn": ["{t} ವೀಡಿಯೋ ತೋರಿಸಿ", "{t} ವೀಡಿಯೋಗಳು", "{t} ವೀಡಿಯೋ ಹುಡುಕಿ", "!{t} ಬಗ್ಗೆ ವೀಡಿಯೋ ಇದೆಯಾ"],
        "kn-Latn": ["{t} video thorisi", "{t} videos", "{t} video hudki", "!{t} bagge video ideya"],
        "ta": ["{t} வீடியோ காட்டு", "{t} வீடியோக்கள்", "{t} வீடியோ தேடு", "!{t} பற்றி வீடியோ இருக்கா"],
        "te": ["{t} వీడియోలు చూపించు", "{t} వీడియో", "{t} వీడియోలు వెతకండి", "!{t} గురించి వీడియో ఉందా"],
    },
    "IMAGE": {
        "en": ["{t} photos", "show me photos of {t}", "find pictures of {t}", "{t} images", "!any pics of {t}", "!pictures from the {t}"],
        "hi": ["{t} की फोटो दिखाओ", "{t} की तस्वीरें", "!{t} की फोटो ढूंढो"],
        "hi-Latn": ["{t} ki photos dikhao", "{t} ki pics", "!{t} ki photo dhundo"],
        "kn": ["{t} ಫೋಟೋ ತೋರಿಸಿ", "{t} ಫೋಟೋಗಳು", "!{t} ಚಿತ್ರಗಳನ್ನು ಹುಡುಕಿ"],
        "kn-Latn": ["{t} photo thorisi", "{t} photos", "!{t} photo hudki"],
        "ta": ["{t} புகைப்படங்கள் காட்டு", "{t} போட்டோ", "!{t} படங்கள் தேடு"],
        "te": ["{t} ఫోటోలు చూపించు", "{t} ఫోటోలు", "!{t} చిత్రాలు వెతకండి"],
    },
    "FILE": {
        "en": ["{t} documents", "find the {t} pdf", "show files about {t}", "!any {t} documents shared"],
        "hi": ["{t} की फाइल दिखाओ", "!{t} के दस्तावेज़"],
        "hi-Latn": ["{t} ki file dikhao", "!{t} ka pdf"],
        "kn": ["{t} ಫೈಲ್ ತೋರಿಸಿ", "!{t} ದಾಖಲೆಗಳು"],
        "kn-Latn": ["{t} file thorisi", "!{t} documents"],
        "ta": ["{t} கோப்பு காட்டு", "!{t} ஆவணங்கள்"],
        "te": ["{t} ఫైల్ చూపించు", "!{t} పత్రాలు"],
    },
    "ALL": {
        "en": ["posts about {t}", "what are people posting about {t}", "show posts on {t}", "find posts about {t}", "!anything posted about {t}", "!latest {t} posts"],
        "hi": ["{t} के बारे में पोस्ट", "{t} पर पोस्ट दिखाओ", "!लोग {t} के बारे में क्या पोस्ट कर रहे हैं"],
        "hi-Latn": ["{t} ke baare mein posts", "{t} pe posts dikhao", "!log {t} ke baare mein kya post kar rahe hain"],
        "kn": ["{t} ಬಗ್ಗೆ ಪೋಸ್ಟ್‌ಗಳು", "{t} ಬಗ್ಗೆ ಪೋಸ್ಟ್ ತೋರಿಸಿ", "!{t} ಬಗ್ಗೆ ಜನ ಏನು ಪೋಸ್ಟ್ ಮಾಡಿದ್ದಾರೆ"],
        "kn-Latn": ["{t} bagge posts", "{t} bagge post thorisi", "!{t} bagge jana enu post madidare"],
        "ta": ["{t} பற்றிய பதிவுகள்", "{t} பற்றி பதிவுகள் காட்டு", "!{t} பற்றி மக்கள் என்ன பதிவிட்டார்கள்"],
        "te": ["{t} గురించి పోస్ట్‌లు", "{t} గురించి పోస్ట్‌లు చూపించు", "!{t} గురించి ఎవరు ఏమి పోస్ట్ చేశారు"],
    },
}
# kind -> lang -> templates with no topic (query "")
CONTENT_ANY = {
    "VIDEO": {"en": ["show me videos", "watch videos", "!any new videos"], "hi": ["वीडियो दिखाओ", "!नए वीडियो"], "hi-Latn": ["videos dikhao", "!naye videos"],
              "kn": ["ವೀಡಿಯೋ ತೋರಿಸಿ", "!ಹೊಸ ವೀಡಿಯೋಗಳು"], "kn-Latn": ["video thorisi", "!hosa videos"], "ta": ["வீடியோ காட்டு", "!புதிய வீடியோக்கள்"],
              "te": ["వీడియోలు చూపించు", "!కొత్త వీడియోలు"]},
    "IMAGE": {"en": ["show photos", "!latest pictures"], "hi": ["फोटो दिखाओ"], "hi-Latn": ["photos dikhao"], "kn": ["ಫೋಟೋ ತೋರಿಸಿ"], "kn-Latn": ["photo thorisi"],
              "ta": ["போட்டோ காட்டு"], "te": ["ఫోటోలు చూపించు"]},
    "FILE": {"en": ["show shared files"]},
    "ALL": {"en": ["show me new posts", "what's new in explore", "!what are people posting"], "hi": ["नई पोस्ट दिखाओ", "!क्या नया पोस्ट हुआ"],
            "hi-Latn": ["nayi posts dikhao", "!kya naya post hua"], "kn": ["ಹೊಸ ಪೋಸ್ಟ್ ತೋರಿಸಿ"], "kn-Latn": ["hosa post thorisi"], "ta": ["புதிய பதிவுகள் காட்டு"],
            "te": ["కొత్త పోస్ట్‌లు చూపించు"]},
}
# A person: PEOPLE finds their profile; POSTS_BY shows what they posted (ALL with their name as the query).
PEOPLE = {
    "en": ["search for {n}'s profile", "find my friend {n}", "look up {n}", "who is {n} on bucks", "{n}'s profile", "!open {n}'s profile", "!connect with {n}"],
    "hi": ["{n} की प्रोफाइल दिखाओ", "{n} को ढूंढो", "!मेरे दोस्त {n} को खोजो"],
    "hi-Latn": ["{n} ki profile dikhao", "{n} ko dhundo", "!mere dost {n} ko search karo"],
    "kn": ["{n} ಪ್ರೊಫೈಲ್ ತೋರಿಸಿ", "{n} ಅವರನ್ನು ಹುಡುಕಿ", "!ನನ್ನ ಗೆಳೆಯ {n} ಅವರನ್ನು ಹುಡುಕಿ"],
    "kn-Latn": ["{n} profile thorisi", "{n} avrannu hudki", "!nanna friend {n} na hudki"],
    "ta": ["{n} சுயவிவரம் காட்டு", "{n} ஐ தேடு", "!என் நண்பர் {n} ஐ தேடு"],
    "te": ["{n} ప్రొఫైల్ చూపించు", "{n} ని వెతకండి", "!నా స్నేహితుడు {n} ని వెతకండి"],
}
POSTS_BY = {
    "en": ["{n}'s posts", "show posts by {n}", "!what has {n} posted"],
    "hi": ["{n} की पोस्ट दिखाओ", "!{n} ने क्या पोस्ट किया"],
    "hi-Latn": ["{n} ki posts dikhao", "!{n} ne kya post kiya"],
    "kn": ["{n} ಅವರ ಪೋಸ್ಟ್ ತೋರಿಸಿ", "!{n} ಏನು ಪೋಸ್ಟ್ ಮಾಡಿದ್ದಾರೆ"],
    "kn-Latn": ["{n} avara post thorisi", "!{n} enu post madidare"],
    "ta": ["{n} பதிவுகள் காட்டு", "!{n} என்ன பதிவிட்டார்"],
    "te": ["{n} పోస్ట్‌లు చూపించు", "!{n} ఏమి పోస్ట్ చేశారు"],
}

# ---------- Malayalam (ml) and Manglish (ml-Latn), added 2026-11-20 at the user's request; needs a native speaker's review ----------
_ML_PLACES = {  # canonical: (ml forms, ml "to" forms, ml-Latn forms, ml-Latn "to" forms)
    "MG Road": (["എം.ജി. റോഡ്"], ["എം.ജി. റോഡിലേക്ക്"], ["MG road"], ["MG roadilekku"]),
    "Koramangala": (["കോരമംഗല"], ["കോരമംഗലയിലേക്ക്"], ["Koramangala"], ["Koramangalayilekku"]),
    "Indiranagar": (["ഇന്ദിരാനഗർ"], ["ഇന്ദിരാനഗറിലേക്ക്"], ["Indiranagar"], ["Indiranagarilekku"]),
    "Jayanagar": (["ജയനഗർ"], ["ജയനഗറിലേക്ക്"], ["Jayanagar"], ["Jayanagarilekku"]),
    "Whitefield": (["വൈറ്റ്ഫീൽഡ്"], ["വൈറ്റ്ഫീൽഡിലേക്ക്"], ["Whitefield"], ["Whitefieldilekku"]),
    "Majestic": (["മജസ്റ്റിക്"], ["മജസ്റ്റിക്കിലേക്ക്"], ["Majestic"], ["Majesticilekku"]),
    "Kempegowda airport": (["എയർപോർട്ട്", "വിമാനത്താവളം"], ["എയർപോർട്ടിലേക്ക്", "വിമാനത്താവളത്തിലേക്ക്"], ["airport"], ["airportilekku"]),
    "Nexus Mall": (["നെക്സസ് മാൾ"], ["നെക്സസ് മാളിലേക്ക്"], ["Nexus mall"], ["Nexus mallilekku"]),
    "HSR Layout": (["എച്ച്എസ്ആർ ലേഔട്ട്"], ["എച്ച്എസ്ആർ ലേഔട്ടിലേക്ക്"], ["HSR layout"], ["HSR layoutilekku"]),
    "Electronic City": (["ഇലക്ട്രോണിക് സിറ്റി"], ["ഇലക്ട്രോണിക് സിറ്റിയിലേക്ക്"], ["Electronic city"], ["Electronic cityilekku"]),
    "Marathahalli": (["മാറത്തഹള്ളി"], ["മാറത്തഹള്ളിയിലേക്ക്"], ["Marathahalli"], ["Marathahalliyilekku"]),
    "Hebbal": (["ഹെബ്ബാൾ"], ["ഹെബ്ബാളിലേക്ക്"], ["Hebbal"], ["Hebbalilekku"]),
    "Banashankari": (["ബനശങ്കരി"], ["ബനശങ്കരിയിലേക്ക്"], ["Banashankari"], ["Banashankariyilekku"]),
}
for _p, (_ml, _mlt, _lat, _latt) in _ML_PLACES.items():
    PLACES[_p].update({"ml": _ml, "ml-Latn": _lat})
    PLACE_TO[_p].update({"ml": _mlt, "ml-Latn": _latt})
VEHICLES["AUTO"].update({"ml": ["ഓട്ടോ"], "ml-Latn": ["auto"]})
VEHICLES["CAB"].update({"ml": ["ടാക്സി", "കാർ"], "ml-Latn": ["taxi", "cab"]})
VEHICLES["BIKE"].update({"ml": ["ബൈക്ക്"], "ml-Latn": ["bike"]})
for _i, (_ml, _lat) in {
    "sugar": (["പഞ്ചസാര"], ["panchasara"]), "milk": (["പാൽ"], ["paal"]), "eggs": (["മുട്ട"], ["mutta"]), "rice": (["അരി"], ["ari"]),
    "wheat flour": (["ഗോതമ്പ് പൊടി"], ["gothambu podi", "atta"]), "vegetables": (["പച്ചക്കറി"], ["pachakkari"]), "tomatoes": (["തക്കാളി"], ["thakkali"]),
    "onions": (["ഉള്ളി", "സവാള"], ["ulli", "savala"]), "cooking oil": (["എണ്ണ"], ["enna"]), "curd": (["തൈര്"], ["thairu"]), "paneer": (["പനീർ"], ["paneer"]),
    "chicken": (["ചിക്കൻ", "കോഴി ഇറച്ചി"], ["chicken"]), "bread": (["ബ്രെഡ്"], ["bread"]), "biryani": (["ബിരിയാണി"], ["biriyani"]),
    "pharmacy": (["മെഡിക്കൽ ഷോപ്പ്"], ["medical shop"]), "plumber": (["പ്ലംബർ"], ["plumber"]), "electrician": (["ഇലക്ട്രീഷ്യൻ"], ["electrician"]),
    "tailor": (["തയ്യൽക്കാരൻ"], ["tailor"]), "doctor": (["ഡോക്ടർ"], ["doctor"]), "carpenter": (["ആശാരി"], ["aashari", "carpenter"]),
    "cook": (["പാചകക്കാരൻ"], ["cook"]), "mechanic": (["മെക്കാനിക്ക്"], ["mechanic"]), "house cleaning": (["വീട്ടുജോലിക്കാരി"], ["veettujolikkari"]),
    "AC repair": (["എസി റിപ്പയർ"], ["AC repair"]), "painter": (["പെയിന്റർ"], ["painter"]),
}.items():
    ITEMS[_i].update({"ml": _ml, "ml-Latn": _lat})
SORTS["PRICE"].update({"ml": ["വില അനുസരിച്ച് കാണിക്കൂ", "കുറഞ്ഞ വില ആദ്യം", "!വില കുറഞ്ഞത് ആദ്യം"],
                       "ml-Latn": ["vila anusarichu kaanikku", "kuranja vila aadyam", "!cheap aadyam"]})
SORTS["NEAR"].update({"ml": ["അടുത്തുള്ളവ ആദ്യം കാണിക്കൂ", "അടുത്തുള്ളത് ആദ്യം", "!ഏറ്റവും അടുത്തുള്ളവ"],
                      "ml-Latn": ["aduthullathu aadyam kaanikku", "aduthullathu aadyam", "!ettavum aduthullathu"]})
SORTS["TRUST"].update({"ml": ["കൂടുതൽ ശുപാർശ ചെയ്തവ ആദ്യം", "റേറ്റിംഗ് അനുസരിച്ച് കാണിക്കൂ", "!വിശ്വസനീയമായവ ആദ്യം"],
                       "ml-Latn": ["most recommended aadyam", "rating anusarichu kaanikku", "!trusted aadyam"]})
RIDE.update({"ml": ["{pt} {v} വേണം", "{pt} {v} ബുക്ക് ചെയ്യൂ", "എനിക്ക് {pt} പോകണം, {v} വിളിക്കൂ", "{pt} പോകാൻ {v} വേണം", "{pt} ഒരു {v} അയക്കൂ",
                    "!വേഗം {pt} ഒരു {v} വേണം", "!{pt} പോകണം, {v} ബുക്ക് ചെയ്യൂ"],
             "ml-Latn": ["{pt} {v} venam", "{pt} {v} book cheyyu", "enikku {pt} pokanam {v} vilikku", "{pt} pokan {v} venam", "{pt} oru {v} ayakku",
                         "!vegam {pt} {v} venam", "!{pt} pokanam {v} book cheyyu"]})
RIDE_NO_VEHICLE.update({"ml": ["എന്നെ {pt} കൊണ്ടുപോകൂ", "എനിക്ക് {pt} പോകണം", "!{pt} എത്തിക്കൂ"],
                        "ml-Latn": ["{pt} pokanam", "enne {pt} kondupoku", "!{pt} ethikku"]})
RIDE_NO_PLACE.update({"ml": ["{v} വേണം", "ഒരു {v} വിളിക്കൂ", "!ഒരു {v} അയക്കൂ"], "ml-Latn": ["{v} venam", "oru {v} vilikku", "!oru {v} ayakku"]})
SEARCH.update({"ml": ["{i} വേണം", "അടുത്ത് {i} എവിടെ കിട്ടും", "{i} എവിടെ കിട്ടും", "{i} തിരയൂ", "എനിക്ക് {i} വേണം", "!അടുത്ത് {i} ഉണ്ടോ", "!{i} കാണിക്കൂ"],
               "ml-Latn": ["{i} venam", "aduthu {i} evide kittum", "{i} evide kittum", "{i} thirayu", "enikku {i} venam", "!aduthu {i} undo", "!{i} kaanikku"]})
COMPARE.update({"ml": ["വില കുറഞ്ഞ {i} ഏതാണ്", "{i} താരതമ്യം ചെയ്യൂ", "നല്ല {i} ഏതാണ്", "!ഏറ്റവും നല്ല {i} ഏതാണ്", "!{i} വില താരതമ്യം ചെയ്യൂ"],
                "ml-Latn": ["cheap {i} ethaanu", "best {i} ethaanu", "{i} compare cheyyu", "nalla {i} ethaanu", "!kuranja vilayil {i}", "!ethu {i} aanu nallathu"]})
POST.update({"ml": ["{i} വേണം എന്ന് അഭ്യർത്ഥന പോസ്റ്റ് ചെയ്യൂ", "!അയൽക്കാരോട് {i} ചോദിക്കൂ"],
             "ml-Latn": ["{i} venam ennu request post cheyyu", "!{i} nu request idu"]})
for _t, (_ml, _lat) in {
    "show_activity": (["എന്റെ ഓർഡറുകൾ കാണിക്കൂ", "എന്റെ ഓർഡർ എവിടെ", "!എന്റെ യാത്രകൾ"], ["ente orders kaanikku", "ente order evide", "!ente rides"]),
    "go_online": (["എന്നെ ഓൺലൈൻ ആക്കൂ", "ഡ്യൂട്ടി തുടങ്ങൂ", "!ഓൺലൈൻ ആകണം"], ["online aakku", "duty start cheyyu", "!online aakanam"]),
    "become_provider": (["എന്റെ കട ചേർക്കണം", "എന്റെ വണ്ടി രജിസ്റ്റർ ചെയ്യണം", "!എനിക്ക് വിൽക്കണം"],
                        ["ente kada add cheyyanam", "ente vandi register cheyyanam", "!enikku vilkkanam"]),
    "confirm_pending": (["അതെ", "ശരി", "ഓക്കെ", "!ചെയ്യൂ"], ["athe", "sheri", "ok cheyyu", "!cheyyu"]),
    "cancel_pending": (["വേണ്ട", "റദ്ദാക്കൂ", "!വേണ്ട വിട്ടേക്കൂ"], ["venda", "cancel cheyyu", "!venda vittekku"]),
    "show_map": (["മാപ്പ് കാണിക്കൂ", "!മാപ്പ് തുറക്കൂ"], ["map kaanikku", "!map thurakku"]),
    "help": (["നമസ്കാരം", "ഇന്ന് കാലാവസ്ഥ എങ്ങനെ", "നന്ദി", "!നിങ്ങൾ ആരാണ്"], ["sukhamano", "ninakku enthokke cheyyan pattum", "thanks", "!nee aaraa"]),
}.items():
    FIXED[_t].update({"ml": _ml, "ml-Latn": _lat})
TOPICS.update({"ml": ["പാചകം", "ക്രിക്കറ്റ്", "സംഗീതം", "നൃത്തം", "കല്യാണം", "ഓണം", "കൊടഗ് കാപ്പി"],
               "ml-Latn": ["paachakam", "cricket", "sangeetham", "dance", "kalyanam", "onam", "Coorg coffee"]})
NAMES.update({"ml": ["രവി", "ആശ", "സുരേഷ്", "മീര", "കാവ്യ", "അർജുൻ"], "ml-Latn": ["Ravi", "Asha", "Suresh", "Meera", "Kavya", "Arjun"]})
CONTENT["VIDEO"].update({"ml": ["{t} വീഡിയോ കാണിക്കൂ", "{t} വീഡിയോകൾ", "{t} വീഡിയോ തിരയൂ", "!{t} വീഡിയോ ഉണ്ടോ"],
                         "ml-Latn": ["{t} video kaanikku", "{t} videos", "{t} video thirayu", "!{t} video undo"]})
CONTENT["IMAGE"].update({"ml": ["{t} ഫോട്ടോ കാണിക്കൂ", "{t} ഫോട്ടോകൾ", "!{t} ചിത്രങ്ങൾ തിരയൂ"], "ml-Latn": ["{t} photo kaanikku", "{t} photos", "!{t} photo thirayu"]})
CONTENT["FILE"].update({"ml": ["{t} ഫയൽ കാണിക്കൂ", "!{t} രേഖകൾ"], "ml-Latn": ["{t} file kaanikku", "!{t} documents"]})
CONTENT["ALL"].update({"ml": ["{t} പോസ്റ്റുകൾ", "{t} പോസ്റ്റ് കാണിക്കൂ", "!{t} പറ്റി ആളുകൾ എന്താണ് പോസ്റ്റ് ചെയ്തത്"],
                       "ml-Latn": ["{t} posts", "{t} post kaanikku", "!{t} patti aalukal entha post cheythathu"]})
CONTENT_ANY["VIDEO"].update({"ml": ["വീഡിയോ കാണിക്കൂ", "!പുതിയ വീഡിയോകൾ"], "ml-Latn": ["video kaanikku", "!puthiya videos"]})
CONTENT_ANY["IMAGE"].update({"ml": ["ഫോട്ടോ കാണിക്കൂ"], "ml-Latn": ["photo kaanikku"]})
CONTENT_ANY["ALL"].update({"ml": ["പുതിയ പോസ്റ്റ് കാണിക്കൂ"], "ml-Latn": ["puthiya post kaanikku"]})
PEOPLE.update({"ml": ["{n} പ്രൊഫൈൽ കാണിക്കൂ", "{n} എന്നയാളെ തിരയൂ", "!എന്റെ സുഹൃത്ത് {n} എന്നയാളെ തിരയൂ"],
               "ml-Latn": ["{n} profile kaanikku", "{n} ne thirayu", "!ente friend {n} ne thirayu"]})
POSTS_BY.update({"ml": ["{n} ന്റെ പോസ്റ്റുകൾ കാണിക്കൂ", "!{n} എന്താണ് പോസ്റ്റ് ചെയ്തത്"], "ml-Latn": ["{n} nte posts kaanikku", "!{n} entha post cheythathu"]})

# ---------- Round 4 (2026-11-20): more TRAINING phrasings for what run 2 missed; eval-only ("!") templates are unchanged ----------
# Run 2 misses: post_request read as search (1-2 train phrasings per language), compare read as search, sort/help/cancel thin,
# kn-Latn rides and people lookups, and invented destinations on urgent rides with no place ("jaldi cab").
def _add(table, extra):
    for lang, ts in extra.items():
        table.setdefault(lang, []).extend(ts)

_add(POST, {
    "en": ["can someone nearby lend me {i}", "post that I need {i}", "put out a request: {i}", "tell people I'm looking for {i}",
           "ask around the area for {i}", "broadcast a request for {i}"],
    "hi": ["{i} चाहिए, मोहल्ले में पोस्ट करो", "लोगों से {i} के बारे में पूछो", "{i} की रिक्वेस्ट डाल दो", "आसपास वालों से {i} माँगो"],
    "hi-Latn": ["mohalle mein {i} ke liye post karo", "{i} chahiye sabko batao", "aas paas walon se {i} maango", "{i} ke liye request bhej do",
                "group mein {i} ka post daalo"],
    "kn": ["{i} ಬೇಕು ಅಂತ ಎಲ್ಲರಿಗೂ ಕೇಳಿ", "ಹತ್ತಿರದವರಿಗೆ {i} ಬೇಕು ಅಂತ ಹೇಳಿ", "{i} ಗಾಗಿ ವಿನಂತಿ ಹಾಕಿ"],
    "kn-Latn": ["{i} beku antha ellarigu keli", "hathradavrige {i} beku antha heli", "{i} ge post haaki"],
    "ta": ["{i} வேணும்னு எல்லாருக்கும் சொல்லு", "பக்கத்து வீட்டுக்காரங்க கிட்ட {i} கேளு", "{i} க்கு ஒரு கோரிக்கை போடு"],
    "te": ["{i} కావాలని అందరికీ చెప్పండి", "పక్కింటి వాళ్ళని {i} అడగండి", "{i} కోసం పోస్ట్ పెట్టండి"],
    "ml": ["{i} വേണമെന്ന് എല്ലാവരോടും പറയൂ", "{i} ആർക്കെങ്കിലും ഉണ്ടോ എന്ന് ചോദിക്കൂ", "{i} നു വേണ്ടി പോസ്റ്റ് ഇടൂ"],
    "ml-Latn": ["{i} venam ennu ellarodum parayu", "{i} aarkkenkilum undo ennu chodikku", "{i} kittumo ennu post cheyyu"],
})
_add(COMPARE, {
    "en": ["which shop has the best {i}", "is there a cheaper {i}", "what's the price of {i} at different shops", "find me the best deal on {i}"],
    "hi": ["{i} कहाँ सस्ता मिलेगा", "सबसे सस्ता {i} कहाँ है", "किसका {i} अच्छा है"],
    "hi-Latn": ["{i} sabse sasta kahan milega", "kiska {i} best hai", "{i} ka sabse kam rate", "achha wala {i} batao"],
    "kn": ["ಯಾರ {i} ಚೆನ್ನಾಗಿದೆ", "{i} ಎಲ್ಲಿ ಕಡಿಮೆ ಬೆಲೆಗೆ ಸಿಗುತ್ತೆ", "ಉತ್ತಮ {i} ತೋರಿಸಿ"],
    "kn-Latn": ["yara {i} chennagide", "{i} elli kammi bele ge sigutte", "best {i} thorisi", "olle {i} elli sigutte"],
    "ta": ["யாருடைய {i} நல்லா இருக்கு", "{i} எங்கே மலிவா கிடைக்கும்", "சிறந்த {i} காட்டு"],
    "te": ["ఎవరి {i} బాగుంది", "{i} ఎక్కడ చౌకగా దొరుకుతుంది", "మంచి {i} చూపించు"],
    "ml": ["ആരുടെ {i} ആണ് നല്ലത്", "{i} എവിടെ വില കുറച്ച് കിട്ടും", "നല്ല {i} കാണിക്കൂ"],
    "ml-Latn": ["aarude {i} aanu nallathu", "{i} evide vila kuranju kittum", "best {i} kaanikku", "nalla {i} evide kittum"],
})
_add(SORTS["PRICE"], {"en": ["cheapest first please", "lowest price at the top"], "hi": ["सबसे सस्ता ऊपर"], "hi-Latn": ["kam price wale upar", "price low se high"],
                     "kn": ["ಕಡಿಮೆ ಬೆಲೆಯವು ಮೇಲೆ"], "kn-Latn": ["kammi bele mele"], "ta": ["விலை குறைவானது முதலில்"], "te": ["తక్కువ ధరవి పైన"],
                     "ml": ["വില കുറഞ്ഞവ മുകളിൽ"], "ml-Latn": ["vila kuranjathu mukalil"]})
_add(SORTS["NEAR"], {"en": ["closest ones on top"], "hi": ["पास वाले ऊपर"], "hi-Latn": ["nazdeek wale upar", "paas wale top pe"], "kn": ["ಹತ್ತಿರದವು ಮೇಲೆ"],
                    "kn-Latn": ["hathradavu mele"], "ta": ["அருகில் உள்ளவை மேலே"], "te": ["దగ్గరవి పైన"], "ml": ["അടുത്തുള്ളവ മുകളിൽ"],
                    "ml-Latn": ["aduthullathu mukalil"]})
_add(SORTS["TRUST"], {"en": ["highest rated on top"], "hi": ["अच्छे रिव्यू वाले पहले"], "hi-Latn": ["achhe review wale pehle"],
                     "kn": ["ಒಳ್ಳೆಯ ರೇಟಿಂಗ್ ಇರುವವು ಮೊದಲು"], "kn-Latn": ["olle rating iruvudu modalu"], "ta": ["நல்ல ரேட்டிங் உள்ளவை முதலில்"],
                     "te": ["మంచి రేటింగ్ ఉన్నవి ముందు"], "ml": ["നല്ല റേറ്റിംഗ് ഉള്ളവ ആദ്യം"], "ml-Latn": ["nalla rating ullathu aadyam"]})
_add(FIXED["help"], {"en": ["good evening", "what's up", "nice to meet you"], "hi": ["आप कैसे हो", "शुभ प्रभात"],
                    "hi-Latn": ["tumhara naam kya hai", "hello ji", "good morning ji"], "kn": ["ಹೇಗಿದ್ದೀರಾ", "ನಿಮ್ಮ ಹೆಸರೇನು", "ಶುಭೋದಯ"],
                    "kn-Latn": ["namaskara", "ninna hesaru enu", "chennagiddira"], "ta": ["எப்படி இருக்கீங்க", "உங்க பெயர் என்ன", "காலை வணக்கம்"],
                    "te": ["ఎలా ఉన్నారు", "మీ పేరు ఏమిటి", "శుభోదయం"], "ml": ["സുഖമാണോ", "നിങ്ങളുടെ പേര് എന്താണ്", "സുപ്രഭാതം"],
                    "ml-Latn": ["hello", "ninte peru entha", "good morning"]})
_add(FIXED["cancel_pending"], {"en": ["leave it", "don't do it", "skip"], "hi": ["छोड़ो", "नहीं चाहिए"], "hi-Latn": ["nahi karna", "band karo"],
                              "kn": ["ಬೇಡ ಈಗ", "ನಿಲ್ಲಿಸಿ"], "kn-Latn": ["beda iga", "nillisi"], "ta": ["வேண்டாம் இப்போ", "நிறுத்து"],
                              "te": ["ఇప్పుడు వద్దు", "ఆపండి"], "ml": ["ഇപ്പോൾ വേണ്ട", "നിർത്തൂ"], "ml-Latn": ["ippo venda", "nirthu"]})
_add(FIXED["confirm_pending"], {"en": ["yes do it", "alright", "go for it"], "hi": ["हाँ कर दो", "ठीक"], "hi-Latn": ["kar do", "theek hai karo"],
                               "kn": ["ಹೌದು ಮಾಡಿ", "ಓಕೆ"], "kn-Latn": ["ok maadi", "houdu maadi"], "ta": ["சரி பண்ணுங்க", "ஆமா"],
                               "te": ["సరే చేయండి", "అవును చేయండి"], "ml": ["ശരി ചെയ്യൂ", "അതെ ചെയ്യൂ"], "ml-Latn": ["sheri cheyyu", "athe cheyyu"]})
_add(FIXED["become_provider"], {"en": ["I want to earn money here", "register my business", "how can I become a driver"],
                               "hi": ["मुझे यहाँ कमाना है", "मेरी दुकान रजिस्टर करो"], "hi-Latn": ["main seller banna chahta hoon", "driver banna hai"],
                               "kn": ["ನಾನು ಇಲ್ಲಿ ಸಂಪಾದಿಸಬೇಕು", "ಡ್ರೈವರ್ ಆಗಬೇಕು"], "kn-Latn": ["nanu sampadisbeku", "driver aagbeku"],
                               "ta": ["நான் இங்கே சம்பாதிக்கணும்", "டிரைவர் ஆகணும்"], "te": ["నేను ఇక్కడ సంపాదించాలి", "డ్రైవర్ అవ్వాలి"],
                               "ml": ["എനിക്ക് ഇവിടെ സമ്പാദിക്കണം", "ഡ്രൈവർ ആകണം"], "ml-Latn": ["enikku ivide sambadikkanam", "driver aakanam"]})
_add(FIXED["go_online"], {"en": ["I'm available now", "turn on my duty"], "hi": ["मैं उपलब्ध हूँ"], "hi-Latn": ["main available hoon", "online ho jao"],
                         "kn": ["ನಾನು ಈಗ ಲಭ್ಯ"], "kn-Latn": ["nanu iga available"], "ta": ["நான் இப்போ ரெடி"], "te": ["నేను ఇప్పుడు అందుబాటులో ఉన్నాను"],
                         "ml": ["ഞാൻ ഇപ്പോൾ റെഡി"], "ml-Latn": ["njan ippo ready"]})
_add(PEOPLE, {"en": ["go to {n}'s page", "find {n} on bucks", "search person {n}"], "hi": ["{n} को सर्च करो", "{n} का पेज दिखाओ"],
              "hi-Latn": ["{n} ka page dikhao", "{n} ko search karo"], "kn": ["{n} ಅವರ ಪ್ರೊಫೈಲ್ ಹುಡುಕಿ"], "kn-Latn": ["{n} avara profile hudki", "{n} na profile thorisi"],
              "ta": ["{n} பக்கத்தை காட்டு"], "te": ["{n} పేజీ చూపించు"], "ml": ["{n} യുടെ പേജ് കാണിക്കൂ"], "ml-Latn": ["{n} nte profile kaanikku"]})
_add(RIDE_NO_PLACE, {"en": ["{v} right now", "quick, I need a {v}", "send me a {v} fast"], "hi": ["जल्दी {v} चाहिए", "अभी {v} भेजो"],
                     "hi-Latn": ["abhi {v} chahiye", "turant {v} bhejo", "{v} jaldi bhejo"], "kn": ["ಬೇಗ ಒಂದು {v} ಬೇಕು", "ಈಗಲೇ {v} ಬೇಕು"],
                     "kn-Latn": ["bega {v} beku", "iga {v} beku"], "ta": ["சீக்கிரம் {v} வேணும்", "இப்போவே {v} வேணும்"],
                     "te": ["తొందరగా {v} కావాలి", "ఇప్పుడే {v} కావాలి"], "ml": ["വേഗം {v} വേണം", "ഇപ്പോൾ തന്നെ {v} വേണം"],
                     "ml-Latn": ["vegam {v} venam", "ippo {v} venam"]})
_add(RIDE_NO_VEHICLE, {"kn": ["{pt} ಬಿಡಿ"], "kn-Latn": ["{pt} bidi", "{pt} karedukondu hogi"]})
_add(SEARCH, {"kn-Latn": ["{i} ide na", "{i} sigutta", "{i} order maadi"]})
_add(CONTENT_ANY["VIDEO"], {"kn-Latn": ["videos nodbeku", "ella videos thorisi"]})

# ---------- Round 5 (2026-11-20): run 3 read "show X" for shop items as a posts/people search (18 of 35 search misses).
# Training only ever paired the show-verb with photos, profiles, the map and sorting; these pair it with items and shops.
_add(SEARCH, {
    "en": ["show {i} shops", "show me options for {i}", "is there {i} nearby", "any shops with {i}"],
    "hi": ["{i} वाली दुकानें दिखाओ", "मुझे {i} दिखा दो", "{i} के ऑप्शन दिखाओ", "आसपास {i} है क्या"],
    "hi-Latn": ["{i} wali dukaan dikhao", "mujhe {i} dikha do", "{i} ke options dikhao", "paas mein {i} milega kya", "nazdeek {i} hai kya"],
    "kn": ["{i} ಅಂಗಡಿಗಳನ್ನು ತೋರಿಸಿ", "ನನಗೆ {i} ತೋರಿಸಿ", "{i} ಆಯ್ಕೆಗಳನ್ನು ತೋರಿಸಿ", "ಹತ್ತಿರ {i} ಸಿಗುತ್ತಾ", "ಇಲ್ಲಿ {i} ಇದೆಯಾ"],
    "kn-Latn": ["{i} angadi thorisi", "nange {i} thorisi", "{i} options thorisi", "hathra {i} sigutta", "illi {i} ideya"],
    "ta": ["{i} கடைகளை காட்டு", "எனக்கு {i} காட்டு", "{i} ஆப்ஷன்ஸ் காட்டு", "இங்கே {i} இருக்கா", "அருகில் {i} கிடைக்குமா"],
    "te": ["{i} షాపులు చూపించు", "నాకు {i} చూపించు", "{i} ఆప్షన్లు చూపించు", "ఇక్కడ {i} ఉందా", "దగ్గర {i} దొరుకుతుందా"],
    "ml": ["{i} കടകൾ കാണിക്കൂ", "എനിക്ക് {i} കാണിക്കൂ", "{i} ഓപ്ഷനുകൾ കാണിക്കൂ", "ഇവിടെ {i} ഉണ്ടോ", "അടുത്ത് {i} കിട്ടുമോ"],
    "ml-Latn": ["{i} kadakal kaanikku", "enikku {i} kaanikku", "{i} options kaanikku", "ivide {i} undo", "aduthu {i} kittumo"],
})
