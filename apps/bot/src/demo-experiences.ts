import type {
  Experience,
  ExperienceCategory,
  ExperienceId,
  TimeWindow,
  HowToStep,
  RealInconvenience,
} from "@solo-compass/core";

/**
 * Demo set — 20 Chiang Mai experiences with real coordinates.
 * Used for the bot until we wire up the real seed pipeline.
 */

const NOW = "2026-05-01T00:00:00.000Z";

interface DemoSpec {
  slug: string;
  title: string;
  oneLiner: string;
  whyItMatters: string;
  category: ExperienceCategory;
  coordinates: readonly [number, number];
  addressHint: string;
  placeNameRomanized?: string;
  placeNameLocal?: string;
  bestTimes: readonly TimeWindow[];
  durationMin: number;
  durationMax: number;
  howTo: readonly HowToStep[];
  realInconveniences: readonly RealInconvenience[];
  soloOverall: number;
  soloHint?: string;
}

const DEMOS: readonly DemoSpec[] = [
  {
    slug: "doi_suthep_sunrise_chant",
    title: "Catch the 06:00 monk chanting at Doi Suthep before the tour buses",
    oneLiner: "An hour of bells and Pali up the mountain, mostly to yourself.",
    whyItMatters:
      "Before 07:30 the temple is quiet enough to hear bare feet on tile. Mist sits below the gold chedi and the city is invisible underneath. By 09:00 it is a parking lot.",
    category: "culture",
    coordinates: [98.9219, 18.8049],
    addressHint: "Wat Phra That Doi Suthep, top of the mountain road",
    placeNameRomanized: "Wat Phra That Doi Suthep",
    placeNameLocal: "วัดพระธาตุดอยสุเทพ",
    bestTimes: [{ startHour: 5, endHour: 8, note: "before tour buses arrive" }],
    durationMin: 60,
    durationMax: 90,
    howTo: [
      { order: 1, text: "Take a red songthaew from the zoo gate before 05:00 (~150 THB shared)." },
      { order: 2, text: "Climb the 306-step naga staircase, or use the funicular for 50 THB." },
      { order: 3, text: "Sit on the outer terrace, east side, while the chant runs." },
      { order: 4, text: "Walk three clockwise circuits of the chedi after sunrise." },
    ],
    realInconveniences: [
      { category: "logistics", text: "First songthaew up only fills around 04:30 — be willing to wait or charter (~600 THB)." },
      { category: "etiquette", text: "Cover knees and shoulders. Sarongs at the gate are loaner-only and can run out." },
    ],
    soloOverall: 9,
    soloHint: "Solo travelers blend into morning meditation; nobody will ask why you're alone.",
  },
  {
    slug: "khao_soi_khun_yai_lunch",
    title: "Eat khao soi at Khao Soi Khun Yai before they sell out at 13:00",
    oneLiner: "Family kitchen, four tables, one dish done right since 1986.",
    whyItMatters:
      "Yai's khao soi is brothier and less sweet than the tourist-trail bowls. They open at 10:00, finish the pot by early afternoon, close Sundays.",
    category: "food",
    coordinates: [98.9876, 18.7956],
    addressHint: "Soi off Sri Poom Rd, north of the moat",
    placeNameRomanized: "Khao Soi Khun Yai",
    bestTimes: [{ startHour: 10, endHour: 13 }],
    durationMin: 25,
    durationMax: 40,
    howTo: [
      { order: 1, text: "Walk in, grab any open seat — no host, no menu in English." },
      { order: 2, text: "Say 'khao soi gai' (chicken) or 'nuea' (beef). 60 THB." },
      { order: 3, text: "Add lime, pickled mustard, raw shallot from the tray yourself." },
      { order: 4, text: "Pay the woman at the till on the way out. Cash only." },
    ],
    realInconveniences: [
      { category: "logistics", text: "Closed Sundays. Sells out by 13:00 most days." },
      { category: "crowds", text: "Four tables and shared seating — lunchtime you'll sit with strangers." },
    ],
    soloOverall: 9,
    soloHint: "A solo bowl is normal here. Nobody hovers.",
  },
  {
    slug: "ristr8to_pourover_bar",
    title: "Take the bar seat at Ristr8to and watch the world-champion barista work",
    oneLiner: "Specialty bar where the queue is for the seat, not the takeaway window.",
    whyItMatters:
      "Arnon, the owner, has placed top three at the World Latte Art Championship. Sit at the bar with a single-origin pourover and you watch every cup pulled like a shot card.",
    category: "coffee",
    coordinates: [98.9762, 18.7876],
    addressHint: "Nimmanhaemin Rd, near Soi 3",
    placeNameRomanized: "Ristr8to Coffee",
    bestTimes: [{ startHour: 8, endHour: 11 }],
    durationMin: 30,
    durationMax: 60,
    howTo: [
      { order: 1, text: "Skip the takeaway line, ask for a bar seat." },
      { order: 2, text: "Order a single-origin pourover (~140 THB) — they'll talk you through it." },
      { order: 3, text: "Stay for a second small drink; the bar is a dialog, not a transaction." },
    ],
    realInconveniences: [
      { category: "crowds", text: "Bar has 6 seats. Saturdays after 09:30 expect a wait." },
      { category: "logistics", text: "Closes at 18:00. Closed Wednesdays." },
    ],
    soloOverall: 10,
    soloHint: "Bar seating is built for solo — staff actively chat with single customers.",
  },
  {
    slug: "wat_pha_lat_jungle_trail",
    title: "Hike the Monk's Trail to Wat Pha Lat before the 09:00 heat",
    oneLiner: "Forty-five minutes through jungle to a moss-grown forest temple, no entrance fee.",
    whyItMatters:
      "Orange cloth strips on trees mark the route — same trail the monks have walked since the 1300s. The temple itself is half-ruin, half-shrine, with a stream cutting through the courtyard.",
    category: "nature",
    coordinates: [98.9333, 18.8123],
    addressHint: "Trailhead behind Chiang Mai University, end of Suthep Rd",
    placeNameRomanized: "Wat Pha Lat",
    placeNameLocal: "วัดผาลาด",
    bestTimes: [
      { startHour: 6, endHour: 9, note: "before the heat" },
      { startHour: 16, endHour: 18, note: "afternoon, watch for fading light on descent" },
    ],
    durationMin: 90,
    durationMax: 150,
    howTo: [
      { order: 1, text: "Take a Grab to the trailhead (50 THB). Look for the orange cloth on the first tree." },
      { order: 2, text: "Follow the orange markers up — about 40–50 min, mostly shaded." },
      { order: 3, text: "Sit at the temple stream. Stay 30+ minutes; it earns it." },
      { order: 4, text: "Descend the same way, or walk down the paved road for a flatter route." },
    ],
    realInconveniences: [
      { category: "weather", text: "Trail is slick after rain. April–May heat is brutal even at 08:00." },
      { category: "safety", text: "No phone signal in patches. Tell someone you're going." },
    ],
    soloOverall: 8,
    soloHint: "Common solo hike — you'll see other lone walkers on weekend mornings.",
  },
  {
    slug: "fah_lanna_two_hour_thai",
    title: "Book the late-afternoon two-hour Thai massage at Fah Lanna",
    oneLiner: "Traditional Lanna massage in a garden compound, no bait-and-switch upsell.",
    whyItMatters:
      "Run by a women-led local cooperative. Fixed-price menu, no oils-or-herbs surprise on the bill. The 16:00 slot is quiet — the lunch crowd has left, the evening one hasn't arrived.",
    category: "wellness",
    coordinates: [98.9907, 18.7858],
    addressHint: "Soi 5 Wat Ket, east of the river",
    placeNameRomanized: "Fah Lanna Spa",
    bestTimes: [{ startHour: 14, endHour: 18 }],
    durationMin: 120,
    durationMax: 130,
    howTo: [
      { order: 1, text: "Book online or by phone at least a day ahead — walk-ins are rarely possible." },
      { order: 2, text: "Arrive 10 min early, foot-wash in the garden." },
      { order: 3, text: "Two-hour traditional Thai is 1,200 THB. Tip 100 THB cash if you liked it." },
    ],
    realInconveniences: [
      { category: "logistics", text: "The free shuttle pickup window is narrow — confirm pickup time when booking." },
      { category: "etiquette", text: "Phones-off in the treatment garden is enforced." },
    ],
    soloOverall: 10,
    soloHint: "Solo bookings are the norm here. No pressure for couple's packages.",
  },
  {
    slug: "saturday_walking_street",
    title: "Wander Wualai Saturday Walking Street between 18:00 and 20:00",
    oneLiner: "Silver-quarter night market with actual local craft, not just generic souvenirs.",
    whyItMatters:
      "Wualai is the silversmiths' street — the Saturday market here keeps more local tone than the Sunday Tha Pae one. Get there before 20:00 and the crowd is breathable.",
    category: "culture",
    coordinates: [98.9876, 18.7762],
    addressHint: "Wualai Rd, south of Chiang Mai Gate",
    bestTimes: [{ startHour: 17, endHour: 21, dayOfWeek: [6] }],
    durationMin: 60,
    durationMax: 120,
    howTo: [
      { order: 1, text: "Enter from Chiang Mai Gate side; walk south." },
      { order: 2, text: "Stop at the temple courtyard food court for 40-THB plates." },
      { order: 3, text: "Watch silver hammer-work in the open shopfronts past Soi 3." },
    ],
    realInconveniences: [
      { category: "scam", text: "'Antique' silver from non-shopfront stalls is mostly nickel. Buy from named workshops." },
      { category: "crowds", text: "After 20:30 it's elbow-to-elbow. Go early, leave early." },
    ],
    soloOverall: 9,
    soloHint: "Markets are easy alone — eat at the temple food court, no table commitment.",
  },
  {
    slug: "library_workspace_camp",
    title: "Take a window desk at CAMP @ Maya for a 4-hour focus block",
    oneLiner: "24/7 library-café where the buy-in is one drink for unlimited time.",
    whyItMatters:
      "The wall-of-books backdrop and silent zone upstairs make it the most viable deep-work spot in the city. Drink purchase = 2-hour wifi code; refill resets it.",
    category: "work",
    coordinates: [98.9669, 18.8048],
    addressHint: "5th floor, Maya Lifestyle Mall, Nimman",
    placeNameRomanized: "CAMP @ Maya",
    bestTimes: [
      { startHour: 8, endHour: 11 },
      { startHour: 14, endHour: 17 },
    ],
    durationMin: 120,
    durationMax: 240,
    howTo: [
      { order: 1, text: "Buy any drink at the counter; receipt has a 2-hour wifi code." },
      { order: 2, text: "Climb to the upper level — silent zone, no calls." },
      { order: 3, text: "Re-buy at the 2-hour mark for a fresh code." },
    ],
    realInconveniences: [
      { category: "crowds", text: "Exam season (May, October) it fills by 09:00 and you'll stand." },
      { category: "logistics", text: "Outlets at window seats only. Bring an extension cord if you can." },
    ],
    soloOverall: 10,
    soloHint: "Designed for solo work. Headphones on = nobody approaches you.",
  },
  {
    slug: "sunday_walking_street",
    title: "Walk Tha Pae Sunday Walking Street starting at the east gate at 17:00",
    oneLiner: "Largest weekly market in the old city — start east, go before dusk.",
    whyItMatters:
      "Three temple courtyards become food courts for the night. Start at Tha Pae Gate while the sun is still up — light hits the chedis, you can still see what you're buying.",
    category: "culture",
    coordinates: [98.9931, 18.7872],
    addressHint: "Ratchadamnoen Rd, runs from Tha Pae Gate west",
    bestTimes: [{ startHour: 16, endHour: 21, dayOfWeek: [0] }],
    durationMin: 90,
    durationMax: 180,
    howTo: [
      { order: 1, text: "Enter at Tha Pae Gate before 17:30 for golden light." },
      { order: 2, text: "Eat at Wat Phan On courtyard — the food court is on temple grounds." },
      { order: 3, text: "Buy at workshops with people working visible — hand-pressed coconut sugar etc." },
    ],
    realInconveniences: [
      { category: "scam", text: "'Hill tribe handmade' often isn't. Look for sellers actually weaving on the spot." },
      { category: "crowds", text: "After 19:00 the main road is shoulder-traffic. Side sois are calmer." },
    ],
    soloOverall: 9,
  },
  {
    slug: "warorot_market_breakfast",
    title: "Eat breakfast at Warorot Market's upstairs food court at 07:00",
    oneLiner: "Wholesale flower market downstairs, century-old breakfast counters upstairs.",
    whyItMatters:
      "The locals' market — 90% Thai, no English menus, prices are real. The upstairs food court has stalls older than most countries' independence dates.",
    category: "food",
    coordinates: [98.9938, 18.7903],
    addressHint: "East of the river, north of Tha Pae",
    placeNameRomanized: "Warorot Market",
    placeNameLocal: "ตลาดวโรรส",
    bestTimes: [{ startHour: 6, endHour: 9 }],
    durationMin: 30,
    durationMax: 60,
    howTo: [
      { order: 1, text: "Walk through the flower market on the river side — free, beautiful." },
      { order: 2, text: "Climb the back stairs to the food court (signs in Thai only)." },
      { order: 3, text: "Point at any plate that looks busy. 30–50 THB." },
    ],
    realInconveniences: [
      { category: "logistics", text: "Most stalls cash-only. ATM nearby but on the ground floor." },
      { category: "crowds", text: "Saturdays before 08:00 the market road is jammed with delivery scooters." },
    ],
    soloOverall: 8,
  },
  {
    slug: "huay_tung_tao_lake_lunch",
    title: "Take a bamboo hut at Huay Tung Tao for lake-side fish lunch",
    oneLiner: "Reservoir north of town with stilted huts on the water — eat with your feet over the lake.",
    whyItMatters:
      "Locals' weekend lunch spot. You rent a bamboo platform for the duration, food comes in waves, you can swim between courses. Quieter on weekdays.",
    category: "nature",
    coordinates: [98.9217, 18.8762],
    addressHint: "Huay Tung Tao Reservoir, north of the city",
    bestTimes: [{ startHour: 11, endHour: 15 }],
    durationMin: 90,
    durationMax: 180,
    howTo: [
      { order: 1, text: "Grab a Grab from the old city (~150 THB)." },
      { order: 2, text: "Hut rental is 100 THB; staff bring menus." },
      { order: 3, text: "Order tilapia ('pla pao'), papaya salad, bamboo rice. ~250 THB total." },
      { order: 4, text: "Swim if you brought a swimsuit. The far end of the lake is cleaner." },
    ],
    realInconveniences: [
      { category: "weather", text: "Rainy season (Jun–Oct) the huts can flood; check before going." },
      { category: "logistics", text: "Grabs back to town are scarce after 16:00. Have one called when you order food." },
    ],
    soloOverall: 7,
    soloHint: "Solo lunches happen but most huts are families. Pick a corner one.",
  },
  {
    slug: "wat_chedi_luang_dusk",
    title: "Sit at Wat Chedi Luang at 18:30 for the chant and the chedi at blue hour",
    oneLiner: "The half-collapsed 14th-century chedi, lit, while monks chant in the wooden viharn.",
    whyItMatters:
      "Inside the wooden viharn, monks chant evening pali at 18:00–19:00. Step out and the chedi is lit against blue sky. Free, central, somehow uncrowded.",
    category: "culture",
    coordinates: [98.986, 18.7872],
    addressHint: "Center of the old city, Prapokkloa Rd",
    placeNameRomanized: "Wat Chedi Luang",
    placeNameLocal: "วัดเจดีย์หลวง",
    bestTimes: [{ startHour: 18, endHour: 19, note: "evening chant 18:00–19:00" }],
    durationMin: 30,
    durationMax: 60,
    howTo: [
      { order: 1, text: "Enter via the main gate (40 THB foreigner ticket)." },
      { order: 2, text: "Sit in the wooden viharn, back row. Stay through one full chant cycle." },
      { order: 3, text: "Walk a clockwise circuit of the chedi as the lights come on." },
    ],
    realInconveniences: [
      { category: "etiquette", text: "Feet must point away from the Buddha. Locals will shift you politely if you forget." },
      { category: "crowds", text: "Tour group window 17:30–18:00. Arrive at 18:15 and they're leaving." },
    ],
    soloOverall: 9,
  },
  {
    slug: "graph_one_book_one_coffee",
    title: "Read for 90 minutes at Graph Café in the old city with the door drinks",
    oneLiner: "Slow-pour cocktail-bar-meets-cafe, dim light, designed for solo time.",
    whyItMatters:
      "Concrete and dark wood, spotlight at every two-seat table. The 'Door Drinks' menu is a one-shot weekly experiment. Quiet enough to read, slow enough that no one rushes you out.",
    category: "coffee",
    coordinates: [98.9876, 18.7895],
    addressHint: "Soi 6 Singharat Rd, old city",
    placeNameRomanized: "Graph Cafe",
    bestTimes: [{ startHour: 14, endHour: 18 }],
    durationMin: 60,
    durationMax: 120,
    howTo: [
      { order: 1, text: "Order one Door Drink (~180 THB) — ask the barista to explain it." },
      { order: 2, text: "Take a single-seat table along the wall." },
      { order: 3, text: "Stay 90+ min. Refill water freely from the wooden bar." },
    ],
    realInconveniences: [
      { category: "logistics", text: "Tiny — six tables. Past 16:00 weekends you may not get in." },
      { category: "crowds", text: "Photo-walk groups sometimes block the front." },
    ],
    soloOverall: 10,
    soloHint: "Single-seat tables are the design intent here. Bring a book.",
  },
  {
    slug: "thai_cooking_class_morning",
    title: "Take the morning market-then-kitchen Thai cooking class",
    oneLiner: "Half-day class that starts at the market — you pick the chiles, you learn what they do.",
    whyItMatters:
      "Most classes skip the market. The market portion is what makes the dish make sense — you see the difference between palm sugar and white sugar, between bird's-eye and long chiles.",
    category: "food",
    coordinates: [98.9912, 18.7834],
    addressHint: "Most classes start at Somphet or Warorot market",
    bestTimes: [{ startHour: 8, endHour: 13 }],
    durationMin: 240,
    durationMax: 300,
    howTo: [
      { order: 1, text: "Book a class with a market visit — confirm the day before." },
      { order: 2, text: "Wear closed shoes. Markets are wet floors." },
      { order: 3, text: "Pick the harder dishes (massaman, khao soi paste) — you can buy pad thai mix anywhere." },
    ],
    realInconveniences: [
      { category: "logistics", text: "Quality varies wildly. Schools that take >8 students per session are usually a worse experience." },
      { category: "weather", text: "Rainy days the market portion is shortened." },
    ],
    soloOverall: 9,
    soloHint: "Most participants are solo. Group cooking is a natural ice-breaker.",
  },
  {
    slug: "north_gate_jazz_jam",
    title: "Catch the Tuesday jazz jam at North Gate Jazz Co-Op from 21:30",
    oneLiner: "Open jam, real players, no cover charge.",
    whyItMatters:
      "Tuesdays a rotating cast of touring and local players sits in. House band sets at 21:30, jam from ~22:30. Crowd spills onto the corner — drink in hand, music drifting out.",
    category: "nightlife",
    coordinates: [98.9869, 18.7951],
    addressHint: "Corner of Sri Poom and Manee Nopparat, opposite the moat's north gate",
    placeNameRomanized: "North Gate Jazz Co-Op",
    bestTimes: [{ startHour: 21, endHour: 24, dayOfWeek: [2] }],
    durationMin: 90,
    durationMax: 180,
    howTo: [
      { order: 1, text: "Arrive 21:00 to get a seat; standing-room-only by 22:00." },
      { order: 2, text: "Beer ~120 THB. No menu pressure." },
      { order: 3, text: "Sit upstairs balcony for breathing room with sightline to the stage." },
    ],
    realInconveniences: [
      { category: "crowds", text: "Tuesdays are a known event — by 22:30 the sidewalk is the venue." },
      { category: "safety", text: "Walking back through the old city after midnight is fine; the moat road less so. Grab one back if your guesthouse is far." },
    ],
    soloOverall: 8,
    soloHint: "Solo at a jazz bar reads as serious-listener. Take a stool, not a table.",
  },
  {
    slug: "san_kamphaeng_hot_spring_soak",
    title: "Soak at San Kamphaeng hot springs for the late-afternoon empty hour",
    oneLiner: "Public hot spring with pools and private rooms an hour east of town.",
    whyItMatters:
      "Tour buses come 10:00–14:00. Show up at 16:00 and the pools are mostly local families. Rentable private rooms are 200 THB and have their own piped-in spring water.",
    category: "wellness",
    coordinates: [99.1318, 18.7565],
    addressHint: "San Kamphaeng Hot Springs, east of Chiang Mai",
    bestTimes: [{ startHour: 16, endHour: 18 }],
    durationMin: 90,
    durationMax: 150,
    howTo: [
      { order: 1, text: "Charter a Grab one-way (~350 THB). Negotiate return with the driver." },
      { order: 2, text: "Entrance: 100 THB foreigner. Private room: +200 THB / 30 min." },
      { order: 3, text: "Buy eggs to boil in the spring (10 THB / 6 eggs) — local ritual, takes 7 minutes." },
    ],
    realInconveniences: [
      { category: "logistics", text: "Public transit is unreliable. Confirm a return Grab before going in." },
      { category: "etiquette", text: "Public pools require a swimsuit, not undergarments. Private rooms are private." },
    ],
    soloOverall: 8,
    soloHint: "Private room makes solo soaking comfortable; the public pool is family-coded.",
  },
  {
    slug: "old_city_temple_chedis_walk",
    title: "Walk a four-temple loop inside the moat between 07:30 and 09:30",
    oneLiner: "Free, self-guided, quietest hour for the four big old-city wats.",
    whyItMatters:
      "Wat Phra Singh, Wat Chedi Luang, Wat Phan Tao, Wat Chiang Man — all walkable in 90 minutes. Before 09:30 you're ahead of every tour bus. By 10:00 they all become photo-stop traffic.",
    category: "culture",
    coordinates: [98.984, 18.7886],
    addressHint: "Old city center; loop through the four wats",
    bestTimes: [{ startHour: 7, endHour: 10 }],
    durationMin: 75,
    durationMax: 120,
    howTo: [
      { order: 1, text: "Start at Wat Phra Singh (west). Free entry; donate 20 THB." },
      { order: 2, text: "East to Wat Phan Tao — small, all teak, often empty." },
      { order: 3, text: "Wat Chedi Luang next door — 40 THB foreigner ticket." },
      { order: 4, text: "End at Wat Chiang Man, the city's oldest. Sit in the back of the viharn." },
    ],
    realInconveniences: [
      { category: "etiquette", text: "Knees and shoulders covered at all four. Wat Phra Singh has loaner sarongs." },
      { category: "weather", text: "April–May the cobbles are oven-hot by 10:00. Move fast or wait until afternoon." },
    ],
    soloOverall: 9,
    soloHint: "Self-paced loop is built for solo. No guide needed.",
  },
  {
    slug: "mae_kha_canal_walk_evening",
    title: "Walk the restored Mae Kha canal walkway at dusk",
    oneLiner: "Recently uncovered side-canal turned linear park — one of the city's quiet recent wins.",
    whyItMatters:
      "The Mae Kha was a sewer for thirty years. The 2023 restoration cleaned a 1km stretch and ran a wood walkway alongside. Locals stroll it at dusk; it has not yet shown up in guidebooks.",
    category: "hidden",
    coordinates: [98.991, 18.7806],
    addressHint: "Mae Kha canal, runs north–south through the south of the old city",
    placeNameRomanized: "Khlong Mae Kha walkway",
    bestTimes: [{ startHour: 17, endHour: 19 }],
    durationMin: 30,
    durationMax: 60,
    howTo: [
      { order: 1, text: "Start at Chang Klan / Loi Kroh intersection." },
      { order: 2, text: "Walk south along the wood deck. Roughly 1 km of restored stretch." },
      { order: 3, text: "Stop at one of the sois with a noodle cart. Plates 40 THB." },
    ],
    realInconveniences: [
      { category: "weather", text: "Smell can return after heavy rain — restoration is partial." },
      { category: "safety", text: "Some unlit gaps where the walkway hasn't been finished. Keep a phone torch." },
    ],
    soloOverall: 9,
  },
  {
    slug: "umong_tunnel_meditation",
    title: "Sit in the 700-year-old tunnels at Wat Umong before 09:00",
    oneLiner: "Forest temple west of town with brick tunnels you can sit inside.",
    whyItMatters:
      "Built in 1297 for a monk who saw visions. The tunnels stay 24°C even in May. Sit inside one with the painted Buddha and the cool gets into your spine.",
    category: "culture",
    coordinates: [98.9486, 18.7864],
    addressHint: "Wat Umong, west of the old city, edge of the forest",
    placeNameRomanized: "Wat U-Mong",
    placeNameLocal: "วัดอุโมงค์",
    bestTimes: [{ startHour: 7, endHour: 10 }],
    durationMin: 45,
    durationMax: 90,
    howTo: [
      { order: 1, text: "Grab to the temple (~80 THB from old city)." },
      { order: 2, text: "Walk past the lake to the tunnel entrance — signs in English." },
      { order: 3, text: "Sit in any tunnel for 20+ minutes. Phone off." },
      { order: 4, text: "Walk the talking-tree forest path on the way out." },
    ],
    realInconveniences: [
      { category: "etiquette", text: "Active monastery. No talking inside the tunnels. Phone silent." },
      { category: "logistics", text: "Donation box on exit — 40–60 THB is right." },
    ],
    soloOverall: 10,
    soloHint: "Meditation tunnels — solo is the natural mode.",
  },
  {
    slug: "akha_ama_origin_pour",
    title: "Order an Akha Ama single-origin at the Hassadhisawee branch",
    oneLiner: "Hill-tribe-grown beans roasted by the family that grew them.",
    whyItMatters:
      "Akha Ama is a single-village direct-trade story — Lee Ayu's mother's village in Mae Suai grows the beans. The Hassadhisawee branch is the smaller one — quieter, same beans.",
    category: "coffee",
    coordinates: [98.9826, 18.7942],
    addressHint: "Hassadhisawee Rd, north old city",
    placeNameRomanized: "Akha Ama Coffee",
    bestTimes: [{ startHour: 8, endHour: 12 }],
    durationMin: 30,
    durationMax: 60,
    howTo: [
      { order: 1, text: "Order whichever single-origin is on the chalkboard (~120 THB)." },
      { order: 2, text: "Ask which village it came from. Staff will tell you." },
      { order: 3, text: "Take a bag of beans home; it's their main income." },
    ],
    realInconveniences: [
      { category: "logistics", text: "Closes Wednesdays. Closes at 17:30." },
      { category: "crowds", text: "The Nimman branch is busier — Hassadhisawee is the calmer choice." },
    ],
    soloOverall: 9,
    soloHint: "Communal benches; staff happy to chat with solo customers.",
  },
  {
    slug: "elephant_nature_park_day",
    title: "Spend a day at Elephant Nature Park as an observation visitor",
    oneLiner: "Sanctuary, no riding, no bathing — just observation of rescued elephants.",
    whyItMatters:
      "Lek Chailert's project — most ethical elephant operation in Thailand. The single-day visit is observation-only; reform-of-the-industry money rather than entertainment money.",
    category: "nature",
    coordinates: [98.7458, 19.171],
    addressHint: "Mae Taeng valley, 60 km north of Chiang Mai (transport included)",
    placeNameRomanized: "Elephant Nature Park",
    bestTimes: [{ startHour: 8, endHour: 16 }],
    durationMin: 480,
    durationMax: 540,
    howTo: [
      { order: 1, text: "Book the single-day visit through the official site (~2,500 THB)." },
      { order: 2, text: "Pickup is 07:30–08:00 from your hotel." },
      { order: 3, text: "Stay through the afternoon — the river crossing happens 14:00." },
    ],
    realInconveniences: [
      { category: "scam", text: "Many copycat 'nature parks' run riding operations under similar names. Book only on elephantnaturepark.org." },
      { category: "logistics", text: "Long day — you won't be back in town until 18:00." },
    ],
    soloOverall: 9,
    soloHint: "Solo travelers are the majority of day-visit guests.",
  },
];

export const DEMO_EXPERIENCES: readonly Experience[] = DEMOS.map((d) => ({
  id: `exp_cmi_${d.slug}` as ExperienceId,
  title: d.title,
  oneLiner: d.oneLiner,
  whyItMatters: d.whyItMatters,
  category: d.category,
  location: {
    coordinates: d.coordinates,
    cityCode: "cmi",
    addressHint: d.addressHint,
    placeNameRomanized: d.placeNameRomanized,
    placeNameLocal: d.placeNameLocal,
  },
  bestTimes: d.bestTimes,
  durationMinutes: { min: d.durationMin, max: d.durationMax },
  howTo: d.howTo,
  realInconveniences: d.realInconveniences,
  soloScore: {
    overall: d.soloOverall,
    breakdown: {
      seatingFriendly: d.soloOverall,
      soloPatronRatio: d.soloOverall,
      staffPressure: d.soloOverall,
      soloPortioning: d.soloOverall,
      ambianceFit: d.soloOverall,
      safety: d.soloOverall,
    },
    hint: d.soloHint,
    basedOnCount: 0,
  },
  sources: [
    {
      type: "blog",
      attribution: "demo seed",
      verifiedAt: NOW,
    },
  ],
  confidence: {
    level: 1,
    lastVerifiedAt: NOW,
    reason: "demo seed data",
    signals: {
      aiScrapeAgeDays: 0,
      passiveGpsHits30d: 0,
      activeReports30d: 0,
      trustedVerifications: 0,
    },
  },
  nearbyExperienceIds: [],
  stats: { completionCount: 0, averageRating: 0 },
  status: "active",
  createdAt: NOW,
  updatedAt: NOW,
}));
