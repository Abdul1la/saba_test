// npm run seed — the development world (Q10), on a database that has run its
// migrations and has no accounts yet. Refuses to run in production, and on a
// database with accounts (it never deletes anything).
//
// This part (S3): the demo logins, Saba's admin, the 8 stores and the 3
// waiting or turned-down ones, the 56 products of MockData with their
// options, stock, flash sales and statuses, brands, banners, the featured
// rail, and the demo photos copied into storage. Slice 4 adds orders, coupons
// and reviews; slice 5 cancelled orders, returns, a suspended shopper and one
// who has not ordered yet; slice 6 the months Saba has marked paid; slice 7
// the web's tickets and the app's chats.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { loadConfig, loadEnvFile } from '../src/config.js'
import { createPool } from '../src/db/pool.js'
import { exec, one, rows } from '../src/db/sql.js'
import { withTransaction } from '../src/db/tx.js'
import type { Connection } from '../src/db/pool.js'
import { fold } from '../src/lib/fold.js'
import { addDays, addMonths, baghdadDay, billingMonth } from '../src/lib/money.js'
import { hashPassword } from '../src/lib/password.js'
import { imageTypeOf, mediaStoreOf, newKey } from '../src/lib/storage.js'
import { storeBills } from '../src/modules/bills.js'
import { nameKey, storeSearchText } from '../src/modules/stores.js'
import { COMMISSION_PERCENT } from '../src/rules.js'
import { userSearchText } from '../src/modules/users.js'

/** Every demo account signs in with this, and its phone number or email. */
const PASSWORD = 'saba12345'

loadEnvFile()
const config = loadConfig()
if (config.env === 'production') {
  console.error('The seed is for development only.')
  process.exit(1)
}
const pool = createPool(config.databaseUrl, 2, config.databaseCa)
const ASSETS = path.resolve('..', 'mobile', 'assets', 'images')

const DAY = 86_400_000
const ago = (days: number, hours = 0) => new Date(Date.now() - days * DAY - hours * 3_600_000)

// ------------------------------------------------------------------- data ---

const CATEGORY: Record<string, number> = {
  'c-phones': 1, 'c-laptops': 2, 'c-headphones': 3, 'c-watches': 4, 'c-cameras': 5, 'c-home': 6, 'c-accessories': 7,
  'c-smartphones': 8, 'c-tablets': 9, 'c-ultrabooks': 10, 'c-gaming-laptops': 11, 'c-phone-cases': 12, 'c-chargers': 13,
}
const PARENT: Record<number, number> = { 8: 1, 9: 1, 10: 2, 11: 2, 12: 7, 13: 7 }
const PHOTO: Record<number, string> = {
  1: 'phones', 2: 'laptops', 3: 'headphones', 4: 'smartwatches', 5: 'cameras', 6: 'home-appliances', 7: 'accessories',
}
const ALL = ['BAGHDAD', 'BASRA', 'NINEVEH', 'ERBIL', 'SULAYMANIYAH', 'DUHOK', 'KIRKUK', 'NAJAF', 'KARBALA', 'BABYLON', 'ANBAR', 'DHI_QAR', 'DIYALA', 'SALAH_AL_DIN', 'WASIT', 'MAYSAN', 'QADISIYAH', 'MUTHANNA', 'HALABJA']

interface StoreSeed {
  demo: string
  name: string
  owner: string
  phone: string
  email?: string
  governorate: string
  status: 'APPROVED' | 'PENDING' | 'REJECTED'
  submitted: number
  answered?: number
  rejection?: string
  description: string
  descriptionAr?: string
  address?: string
  addressAr?: string
  logo?: string
  banner?: string
  delivery?: { areas: string[]; inside: [number, string]; outside?: [number, string] }
}

// MockData.merchants and the web's stores.ts: the same people, numbers and days.
const STORES: StoreSeed[] = [
  { demo: 'm-1', name: 'Nova Electronics', owner: 'Omar Al-Sayed', phone: '+9647711234567', email: 'merchant@saba.app', governorate: 'BAGHDAD', status: 'APPROVED', submitted: 120, answered: 119, description: 'Authorised reseller for phones, laptops and audio.', descriptionAr: 'وكيل معتمد للهواتف والحواسيب والصوتيات.', address: 'Al-Mansour, Street 14', addressAr: 'المنصور، شارع 14', logo: 'stores/nova-logo.jpg', banner: 'stores/nova-banner.jpg', delivery: { areas: ALL, inside: [3000, '1_2_DAYS'], outside: [6000, '3_5_DAYS'] } },
  { demo: 'm-2', name: 'Atlas Home', owner: 'Layla Kareem', phone: '+9647801234567', email: 'merchant2@saba.app', governorate: 'BASRA', status: 'APPROVED', submitted: 112, answered: 111, description: 'Home appliances and kitchen essentials.', descriptionAr: 'أجهزة منزلية ولوازم المطبخ.', address: 'Corniche Street, Al-Ashar', addressAr: 'شارع الكورنيش، العشار', logo: 'stores/atlas-logo.jpg', banner: 'stores/atlas-banner.jpg', delivery: { areas: ['BASRA', 'MAYSAN', 'DHI_QAR', 'MUTHANNA', 'BAGHDAD'], inside: [2000, 'SAME_DAY'], outside: [5000, '2_3_DAYS'] } },
  { demo: 'm-3', name: 'Zakho Mobile', owner: 'Rebwar Salih', phone: '+9647505550131', governorate: 'DUHOK', status: 'APPROVED', submitted: 64, answered: 63, description: 'Phones and accessories, delivered across Duhok the same day.', descriptionAr: 'هواتف وإكسسوارات، توصيل في دهوك في نفس اليوم.', address: 'Kawa Street, Duhok', addressAr: 'شارع كاوا، دهوك', logo: 'stores/store-3-logo.jpg', banner: 'stores/store-3-banner.jpg', delivery: { areas: ['DUHOK', 'ERBIL', 'NINEVEH'], inside: [3000, 'SAME_DAY'], outside: [5000, '1_2_DAYS'] } },
  { demo: 'm-4', name: 'Duhok Home Center', owner: 'Shirin Ahmed', phone: '+9647505550144', governorate: 'DUHOK', status: 'APPROVED', submitted: 58, answered: 57, description: 'Coolers, fans and kitchen appliances for every home.', descriptionAr: 'مبردات ومراوح وأجهزة مطبخ لكل بيت.', address: 'Nohadra Street, Duhok', addressAr: 'شارع نوهدرا، دهوك', logo: 'stores/store-4-logo.jpg', banner: 'stores/store-4-banner.jpg', delivery: { areas: ['DUHOK', 'ERBIL', 'SULAYMANIYAH'], inside: [4000, '1_2_DAYS'], outside: [7000, '2_3_DAYS'] } },
  { demo: 'm-5', name: 'Citadel Electronics', owner: 'Karwan Aziz', phone: '+9647505550157', governorate: 'ERBIL', status: 'APPROVED', submitted: 51, answered: 50, description: 'Laptops and computer accessories, sent anywhere in Iraq.', descriptionAr: 'حواسيب محمولة وملحقاتها، توصيل إلى كل العراق.', address: '100 Meter Road, Erbil', addressAr: 'شارع 100 متر، أربيل', logo: 'stores/store-5-logo.jpg', banner: 'stores/store-5-banner.jpg', delivery: { areas: ALL, inside: [3000, 'SAME_DAY'], outside: [6000, '2_3_DAYS'] } },
  { demo: 'm-6', name: 'Erbil Cool Air', owner: 'Dilan Hussein', phone: '+9647505550162', governorate: 'ERBIL', status: 'APPROVED', submitted: 44, answered: 44, description: 'Air conditioners and fans, installed in Erbil.', descriptionAr: 'مكيفات ومراوح، مع التركيب في أربيل.', address: 'Iskan, Erbil', addressAr: 'الإسكان، أربيل', logo: 'stores/store-6-logo.jpg', banner: 'stores/store-6-banner.jpg', delivery: { areas: ['ERBIL', 'DUHOK', 'SULAYMANIYAH', 'KIRKUK'], inside: [5000, '1_2_DAYS'], outside: [8000, '2_3_DAYS'] } },
  { demo: 'm-7', name: 'Slemani Gadgets', owner: 'Aram Othman', phone: '+9647705550175', governorate: 'SULAYMANIYAH', status: 'APPROVED', submitted: 37, answered: 36, description: 'Phones, tablets and gadgets.', descriptionAr: 'هواتف وأجهزة لوحية وأجهزة ذكية.', address: 'Salim Street, Sulaymaniyah', addressAr: 'شارع سالم، السليمانية', logo: 'stores/store-7-logo.jpg', banner: 'stores/store-7-banner.jpg', delivery: { areas: ['SULAYMANIYAH', 'HALABJA', 'ERBIL', 'KIRKUK'], inside: [3000, 'SAME_DAY'], outside: [6000, '1_2_DAYS'] } },
  { demo: 'm-8', name: 'Mosul Appliances', owner: 'Yasir Younis', phone: '+9647705550188', governorate: 'NINEVEH', status: 'APPROVED', submitted: 30, answered: 29, description: 'Washing machines, fridges and cookers.', descriptionAr: 'غسالات وثلاجات وطباخات.', address: 'Al-Faisaliya, Mosul', addressAr: 'الفيصلية، الموصل', logo: 'stores/store-8-logo.jpg', banner: 'stores/store-8-banner.jpg', delivery: { areas: ['NINEVEH', 'DUHOK', 'ERBIL', 'KIRKUK', 'BAGHDAD'], inside: [4000, '1_2_DAYS'], outside: [7000, '3_5_DAYS'] } },
  { demo: 'babylon', name: 'Babylon Phone House', owner: 'Ali Hassan', phone: '+9647805550121', governorate: 'BABYLON', status: 'PENDING', submitted: 3.2, description: 'Phones, chargers and cases, with repairs in the shop.', address: 'Al-Iskan, Hillah' },
  { demo: 'kufa', name: 'Kufa Home Store', owner: 'Zainab Kadhim', phone: '+9647705550139', governorate: 'NAJAF', status: 'PENDING', submitted: 0.75, description: 'Fans, coolers and small kitchen appliances.', address: 'Al-Rasool Street, Najaf' },
  { demo: 'karbala', name: 'Karbala Tech Point', owner: 'Mustafa Jabbar', phone: '+9647815550146', governorate: 'KARBALA', status: 'REJECTED', submitted: 9, answered: 8, rejection: 'The shop address is missing. Add the street and a landmark, then apply again.', description: 'Laptops and printers.' },
]

const BRANDS = ['Nova', 'Lumen', 'Atlas', 'Kite Audio', 'Orbit']

type Sold = 'plain' | 'phone' | 'laptop'
// MockData._firstProducts (alternating Nova, Atlas) then _moreProducts.
const FIRST: [string, string, string, string, number, number | null, Sold][] = [
  ['Nova X5 Smartphone', 'هاتف نوفا X5 الذكي', 'c-smartphones', 'Nova', 329000, 389000, 'phone'],
  ['Atlas Air Fryer 5L', 'قلاية هوائية أطلس 5 لتر', 'c-home', 'Atlas', 95000, null, 'plain'],
  ['Lumen Book 14 Ultrabook', 'حاسوب لومن بوك 14 النحيف', 'c-ultrabooks', 'Lumen', 675000, null, 'laptop'],
  ['Atlas Steam Iron', 'مكواة بخار أطلس', 'c-home', 'Atlas', 32000, 38000, 'plain'],
  ['Kite Audio Studio Headphones', 'سماعات كايت أوديو ستوديو', 'c-headphones', 'Kite Audio', 145000, null, 'plain'],
  ['Atlas Robot Vacuum', 'مكنسة روبوت أطلس', 'c-home', 'Atlas', 265000, null, 'plain'],
  ['Nova Watch Series 4', 'ساعة نوفا الذكية الإصدار 4', 'c-watches', 'Nova', 189000, 229000, 'plain'],
  ['Atlas Stand Mixer', 'عجّانة أطلس الكهربائية', 'c-home', 'Atlas', 145000, null, 'plain'],
  ['Orbit Mirrorless Camera', 'كاميرا أوربت بدون مرآة', 'c-cameras', 'Orbit', 950000, null, 'plain'],
  ['Atlas Espresso Machine', 'ماكينة إسبريسو أطلس', 'c-home', 'Atlas', 185000, 219000, 'plain'],
  ['Nova Fast Charger 65W', 'شاحن نوفا السريع 65 واط', 'c-chargers', 'Nova', 25000, null, 'plain'],
  ['Atlas Rice Cooker', 'طباخة رز أطلس', 'c-home', 'Atlas', 45000, null, 'plain'],
]
const MORE: [string, string, string, string, number, number | null][] = [
  ['Zagros Z10 Smartphone', 'هاتف زاغروس Z10 الذكي', 'c-smartphones', 'm-3', 289000, 339000],
  ['Zagros Z10 Clear Case', 'غطاء شفاف لهاتف زاغروس Z10', 'c-phone-cases', 'm-3', 9000, null],
  ['Tigris Power Bank 20000mAh', 'باور بانك دجلة 20000 ملي أمبير', 'c-chargers', 'm-3', 32000, null],
  ['Zagros Z7 Smartphone', 'هاتف زاغروس Z7', 'c-smartphones', 'm-3', 199000, null],
  ['Leather Flip Cover', 'غطاء جلد قلاب', 'c-phone-cases', 'm-3', 12500, 15000],
  ['Gara Air Cooler 60L', 'مبردة هواء كارا 60 لتر', 'c-home', 'm-4', 245000, 280000],
  ['Gara Standing Fan', 'مروحة كارا عمودية', 'c-home', 'm-4', 55000, null],
  ['Khabur Water Heater 50L', 'سخان ماء خابور 50 لتر', 'c-home', 'm-4', 175000, null],
  ['Khabur Electric Kettle', 'غلاية كهربائية خابور', 'c-home', 'm-4', 22500, 27500],
  ['Citadel Book 15 Laptop', 'حاسوب سيتادل بوك 15', 'c-ultrabooks', 'm-5', 690000, 790000],
  ['Citadel Gamer 17', 'حاسوب ألعاب سيتادل 17', 'c-gaming-laptops', 'm-5', 1250000, null],
  ['Citadel Book Air 13', 'حاسوب سيتادل بوك إير 13', 'c-ultrabooks', 'm-5', 540000, null],
  ['Erbil Fit Band 3', 'سوار أربيل الرياضي 3', 'c-watches', 'm-5', 45000, 55000],
  ['Wireless Mouse and Keyboard Set', 'طقم فأرة ولوحة مفاتيح لاسلكي', 'c-accessories', 'm-5', 35000, null],
  ['Frost Split AC 1.5 Ton', 'مكيف سبليت فروست 1.5 طن', 'c-home', 'm-6', 620000, 700000],
  ['Frost Split AC 2 Ton', 'مكيف سبليت فروست 2 طن', 'c-home', 'm-6', 780000, null],
  ['Frost Portable AC', 'مكيف فروست متنقل', 'c-home', 'm-6', 410000, null],
  ['Frost Ceiling Fan', 'مروحة سقفية فروست', 'c-home', 'm-6', 48000, null],
  ['Frost Voltage Stabiliser', 'منظم فولتية فروست', 'c-home', 'm-6', 60000, 72000],
  ['Sirwan S8 Smartphone', 'هاتف سيروان S8 الذكي', 'c-smartphones', 'm-7', 355000, null],
  ['Sirwan Kids Tablet', 'تابلت سيروان للأطفال', 'c-tablets', 'm-7', 120000, 150000],
  ['Goizha Fitness Band', 'سوار كويزة الرياضي', 'c-watches', 'm-7', 39000, null],
  ['Magnetic Car Phone Holder', 'حامل هاتف مغناطيسي للسيارة', 'c-accessories', 'm-7', 15000, null],
  ['Sirwan Game Controller', 'ذراع ألعاب سيروان', 'c-accessories', 'm-7', 42500, null],
  ['Hadba Washing Machine 9kg', 'غسالة الحدباء 9 كغم', 'c-home', 'm-8', 385000, 430000],
  ['Hadba Refrigerator 18ft', 'ثلاجة الحدباء 18 قدم', 'c-home', 'm-8', 720000, null],
  ['Hadba Gas Cooker 5 Burners', 'طباخ غاز الحدباء 5 عيون', 'c-home', 'm-8', 265000, null],
  ['Hadba Microwave 30L', 'مايكروويف الحدباء 30 لتر', 'c-home', 'm-8', 98000, 115000],
  ['Orbit Action Camera 4K', 'كاميرا أوربت أكشن 4K', 'c-cameras', 'm-1', 215000, 249000],
  ['Orbit Security Camera Indoor', 'كاميرا أوربت للمراقبة الداخلية', 'c-cameras', 'm-1', 48000, null],
  ['Sirwan Dash Camera', 'كاميرا سروان للسيارة', 'c-cameras', 'm-7', 72000, 89000],
  ['Citadel Webcam 1080p', 'كاميرا ويب سيتاديل 1080p', 'c-cameras', 'm-5', 35000, null],
  ['Zagros Wireless Earbuds', 'سماعات زاغروس اللاسلكية', 'c-headphones', 'm-3', 42000, 55000],
  ['Goizha Over-Ear Headphones', 'سماعات كويژة فوق الأذن', 'c-headphones', 'm-7', 78000, null],
  ['Citadel Gaming Headset', 'سماعة ألعاب سيتاديل', 'c-headphones', 'm-5', 65000, 79000],
  ['Tigris Bluetooth Speaker', 'مكبر صوت دجلة بلوتوث', 'c-accessories', 'm-3', 39000, null],
  ['Zagros Smartwatch Pro', 'ساعة زاغروس الذكية برو', 'c-watches', 'm-3', 125000, 149000],
  ['Nova Watch Lite', 'ساعة نوفا لايت', 'c-watches', 'm-1', 89000, null],
  ['Nova Tab 11', 'جهاز نوفا اللوحي 11', 'c-tablets', 'm-1', 310000, 359000],
  ['Citadel Tab Go', 'جهاز سيتاديل اللوحي جو', 'c-tablets', 'm-5', 165000, null],
  ['Hadba Electric Oven 45L', 'فرن كهربائي الحدباء 45 لتر', 'c-home', 'm-8', 95000, null],
  ['Gara Laptop Cooling Pad', 'قاعدة تبريد حاسوب گارا', 'c-accessories', 'm-4', 22000, 27000],
  ['Frost AC Outdoor Cover', 'غطاء الوحدة الخارجية لمكيف فروست', 'c-home', 'm-6', 18000, null],
  ['Atlas Kitchen Blender', 'خلاط أطلس للمطبخ', 'c-home', 'm-2', 54000, null],
]

// MockData.seededStatus, seededHidden, seededFlashSales (hours from now, on the hour).
const STATUS: Record<number, 'PENDING' | 'DRAFT' | 'REJECTED'> = { 50: 'PENDING', 42: 'DRAFT', 41: 'REJECTED', 4: 'PENDING', 10: 'DRAFT', 56: 'REJECTED' }
const HIDDEN = new Set([51])
const FLASH: Record<number, number> = { 7: 3, 1: 16, 21: 5, 37: 8, 45: 12, 31: 20, 22: 30 }

const BANNERS: [string, string, string, string][] = [
  ['Mid-season sale', 'Up to 40% off selected electronics', 'تخفيضات منتصف الموسم', 'خصم حتى 40% على إلكترونيات مختارة'],
  ['New arrivals', 'Fresh from our merchants', 'وصل حديثاً', 'جديد متاجرنا'],
  ['Free delivery week', 'On orders over 50,000 IQD', 'أسبوع التوصيل المجاني', 'للطلبات فوق 50,000 د.ع'],
  ['Home and kitchen', 'Up to 50% off appliances', 'المنزل والمطبخ', 'خصم حتى 50% على الأجهزة'],
]

// S4: the demo's orders (mock_api_interceptor.dart `_seedMerchantOrders`,
// `_history`), its coupons (`_couponsOf`), and reviews that make the stores'
// ratings real (the user's call, 2026-09-26: better than the demo's totals).

interface Customer {
  name: string
  nameAr: string
  phone: string
  governorate: string
  area: string
  areaAr: string
  street: string
  streetAr: string
  landmark: string
  landmarkAr: string
}

const customer = (
  name: string, nameAr: string, phone: string, governorate: string,
  area: string, areaAr: string, street: string, streetAr: string, landmark: string, landmarkAr: string,
): Customer => ({ name, nameAr, phone, governorate, area, areaAr, street, streetAr, landmark, landmarkAr })

// `_seedCustomers`: who each city's orders go to.
const SARA = customer('Sara Ahmed', 'سارة أحمد', '+9647705550142', 'BAGHDAD', 'Karrada', 'الكرادة', 'Street 62, House 9', 'شارع 62، دار 9', 'Behind the Karrada Maternity Hospital', 'خلف مستشفى الكرادة للولادة')
const YOUSEF = customer('Yousef Karim', 'يوسف كريم', '+9647515550198', 'ERBIL', 'Ainkawa', 'عينكاوا', 'Block 3', 'بلوك 3', 'Next to Ainkawa Mall', 'بجانب مول عينكاوا')
const CITY_CUSTOMERS: Record<string, Customer> = {
  BAGHDAD: SARA,
  ERBIL: YOUSEF,
  BASRA: customer('Zainab Hussein', 'زينب حسين', '+9647805550117', 'BASRA', 'Al-Jazaer', 'الجزائر', 'Street 5, House 21', 'شارع 5، دار 21', 'Near Al-Jazaer Park', 'قرب متنزه الجزائر'),
  DUHOK: customer('Rawand Omar', 'رواند عمر', '+9647505550163', 'DUHOK', 'Masike', 'ماسيكي', 'Street 12', 'شارع 12', 'Behind the Masike mosque', 'خلف جامع ماسيكي'),
  SULAYMANIYAH: customer('Shilan Aziz', 'شيلان عزيز', '+9647705550184', 'SULAYMANIYAH', 'Bakhtiyari', 'بختياري', 'Street 40, House 3', 'شارع 40، دار 3', 'Opposite the Bakhtiyari clinic', 'مقابل مستوصف بختياري'),
  NINEVEH: customer('Omar Younis', 'عمر يونس', '+9647715550126', 'NINEVEH', 'Al-Zuhur', 'الزهور', 'Street 8, House 14', 'شارع 8، دار 14', 'Near Al-Zuhur market', 'قرب سوق الزهور'),
}

// `_historyCustomers`: the shoppers the stores delivered to before today, in the web's order.
const HISTORY_CUSTOMERS: Customer[] = [
  SARA,
  YOUSEF,
  customer('Noor Hadi', 'نور هادي', '+9647805550167', 'BASRA', 'Al-Jazaer', 'الجزائر', 'Street 20, House 7', 'شارع 20، دار 7', 'Near Al-Jazaer Park', 'قرب متنزه الجزائر'),
  customer('Ahmed Jasim', 'أحمد جاسم', '+9647705550211', 'BAGHDAD', 'Al-Mansour', 'المنصور', 'Street 14, House 30', 'شارع 14، دار 30', 'Near Al-Rowad Mosque', 'قرب جامع الرواد'),
  customer('Hawre Kamal', 'هاوري كمال', '+9647505550224', 'SULAYMANIYAH', 'Bakhtiari', 'بختياري', 'Street 40, House 12', 'شارع 40، دار 12', 'Behind Family Mall', 'خلف فاميلي مول'),
  customer('Zahraa Ali', 'زهراء علي', '+9647805550237', 'NAJAF', 'Al-Adala', 'العدالة', 'Street 9, House 4', 'شارع 9، دار 4', 'Near the Kufa University gate', 'قرب باب جامعة الكوفة'),
  customer('Omar Farouk', 'عمر فاروق', '+9647705550243', 'NINEVEH', 'Al-Muthanna', 'المثنى', 'Street 3, House 18', 'شارع 3، دار 18', 'Opposite the Al-Muthanna school', 'مقابل مدرسة المثنى'),
  customer('Lana Aziz', 'لانا عزيز', '+9647505550256', 'DUHOK', 'Malta', 'مالطا', 'Street 11, House 6', 'شارع 11، دار 6', 'Next to Duhok Gate', 'بجانب بوابة دهوك'),
  customer('Mariam Saleh', 'مريم صالح', '+9647705550262', 'KIRKUK', 'Rahimawa', 'رحيم آوه', 'Street 21, House 9', 'شارع 21، دار 9', 'Near the Rahimawa bakery', 'قرب مخبز رحيم آوه'),
  customer('Hussein Karim', 'حسين كريم', '+9647805550278', 'BABYLON', 'Al-Jamiaa', 'الجامعة', 'Street 7, House 25', 'شارع 7، دار 25', 'Behind the Hillah courthouse', 'خلف محكمة الحلة'),
  customer('Dilshad Omer', 'دلشاد عمر', '+9647505550283', 'ERBIL', 'Italian Village', 'القرية الإيطالية', 'Villa 44', 'فيلا 44', 'Near the village gate', 'قرب بوابة القرية'),
]

// `_storeDrivers`: each demo store's own driver, as the admin web has them.
const DRIVERS: Record<string, [string, string, string]> = {
  'm-1': ['Haider Salim', 'حيدر سالم', '+9647705550311'],
  'm-2': ['Mustafa Adnan', 'مصطفى عدنان', '+9647805550322'],
  'm-3': ['Rebwar Sabah', 'ريبوار صباح', '+9647505550333'],
  'm-4': ['Shivan Ahmed', 'شيفان أحمد', '+9647505550344'],
  'm-5': ['Hemin Rashid', 'هيمن رشيد', '+9647505550355'],
  'm-6': ['Karwan Omer', 'كاروان عمر', '+9647505550366'],
  'm-7': ['Aram Jalal', 'آرام جلال', '+9647705550377'],
  'm-8': ['Yasser Thamer', 'ياسر ثامر', '+9647705550388'],
}

// What the reviewed orders said: a shopper's own words, kept as typed; some leave stars only.
const REVIEW_WORDS: (string | null)[] = [
  'Exactly as described. Delivery was quick.',
  null,
  'Good value, but the box arrived a little dented.',
  'وصل بسرعة وكما في الوصف.',
  'Would buy again. The store called before delivering.',
  null,
  'التغليف ممتاز والسعر مناسب.',
]
const REVIEW_STARS = [5, 4, 5, 5, 3, 4, 5, 5, 4, 2]

// S5: the web's cancelled orders (`CANCELS`, website/src/data/orders.ts), its
// returns in every state (`seedReturns`, returns.ts; the app's
// `_historyReturnsOf` is their refunded ones), and customers.ts's suspended
// account and the shopper who has not ordered yet.

/** [store, shopper (HISTORY_CUSTOMERS), days ago, who called it off, their reason, the shopper's note]. */
const CANCELS: [string, number, number, 'SHOPPER' | 'STORE', string, string?][] = [
  ['m-1', 3, 1, 'SHOPPER', 'CHANGED_MIND'],
  ['m-5', 5, 4, 'SHOPPER', 'FOUND_CHEAPER'],
  ['m-2', 2, 9, 'STORE', 'OUT_OF_STOCK'],
  ['m-6', 8, 15, 'SHOPPER', 'DELIVERY_TOO_SLOW'],
  ['m-7', 4, 23, 'STORE', 'ADDRESS_PROBLEM'],
  ['m-8', 6, 38, 'SHOPPER', 'ORDERED_BY_MISTAKE'],
  ['m-3', 7, 52, 'STORE', 'CANNOT_FULFIL'],
  ['m-4', 10, 70, 'SHOPPER', 'OTHER', 'We are moving house next week. I will order again after.'],
]
const RETURN_REASONS = ['DAMAGED', 'WRONG_ITEM', 'NOT_AS_DESCRIBED', 'MISSING_PARTS', 'CHANGED_MIND', 'OTHER']
const SUSPENDED = { phone: '+9647805550278', reason: 'Refused three cash orders at the door in one month.' }
const RANA = customer('Rana Salman', 'رنا سلمان', '+9647805550294', 'KARBALA', 'Al-Abbasiya', 'العباسية', 'Street 5, House 14', 'شارع 5، دار 14', 'Near the Al-Abbasiya market', 'قرب سوق العباسية')

// ------------------------------------------------------------------ seed ---

/** A demo photo copied into storage as a new upload of [owner]'s; null for none. */
const copied = new Map<string, string>()
async function photo(conn: Connection, relative: string, owner: number | null): Promise<string> {
  const cacheKey = `${owner}:${relative}`
  const known = copied.get(cacheKey)
  if (known) return known
  const bytes = await readFile(path.join(ASSETS, relative))
  const type = imageTypeOf(bytes)
  if (!type) throw new Error(`${relative} is not a photo`)
  const key = newKey(type)
  await mediaStoreOf(config).save(key, bytes, type)
  if (owner !== null) {
    await exec(conn, 'INSERT INTO media_files (owner_user_id, storage_key, content_type, byte_size) VALUES (?, ?, ?, ?)', [
      owner,
      key,
      type,
      bytes.length,
    ])
  }
  copied.set(cacheKey, key)
  return key
}

async function account(conn: Connection, role: string, name: string, phone: string, email: string | null, governorate: string | null, hash: string) {
  const inserted = await exec(
    conn,
    // The demo's numbers count as checked, as a code would have done.
    'INSERT INTO users (role, full_name, phone, email, password_hash, governorate, search_text, phone_verified_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW(3))',
    [role, name, phone, email, hash, governorate, userSearchText(name)],
  )
  return inserted.insertId
}

async function seed(conn: Connection) {
  const hash = await hashPassword(PASSWORD)
  await account(conn, 'ADMIN', 'Saba admin', '+9647709999999', 'admin@saba.app', null, hash)
  await account(conn, 'CUSTOMER', 'Amina Saleh', '+9647701234567', 'shopper@saba.app', 'BAGHDAD', hash)

  const storeIds = new Map<string, { id: number; owner: number }>()
  for (const s of STORES) {
    const owner = await account(conn, 'MERCHANT', s.owner, s.phone, s.email ?? null, s.governorate, hash)
    const inserted = await exec(
      conn,
      `INSERT INTO stores (owner_user_id, store_name, name_key, status, rejection_reason, submitted_at, answered_at,
                           governorate, business_type, business_address, business_address_ar, description, description_ar,
                           fee_inside, time_inside, fee_outside, time_outside, rating_sum, rating_count, search_text)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'COMPANY', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        owner,
        s.name,
        nameKey(s.name),
        s.status,
        s.rejection ?? null,
        ago(s.submitted),
        s.answered === undefined ? null : ago(s.answered),
        s.governorate,
        s.address ?? null,
        s.addressAr ?? null,
        s.description,
        s.descriptionAr ?? null,
        s.delivery?.inside[0] ?? null,
        s.delivery?.inside[1] ?? null,
        s.delivery?.outside?.[0] ?? null,
        s.delivery?.outside?.[1] ?? null,
        // No ratings yet: seedBuying's reviews are each store's rating.
        0,
        0,
        storeSearchText(s.name, s.address ?? null, s.addressAr ?? null),
      ],
    )
    const id = inserted.insertId
    storeIds.set(s.demo, { id, owner })
    if (s.delivery) {
      const areas = [...new Set([s.governorate, ...s.delivery.areas])]
      await exec(conn, 'INSERT INTO store_delivery_governorates (store_id, governorate) VALUES ?', [areas.map((a) => [id, a])])
    }
    if (s.logo) await exec(conn, 'UPDATE stores SET logo_url = ? WHERE id = ?', [await photo(conn, s.logo, owner), id])
    if (s.banner) await exec(conn, 'UPDATE stores SET banner_url = ? WHERE id = ?', [await photo(conn, s.banner, owner), id])
  }

  const brandIds = new Map<string, number>()
  for (const name of BRANDS) brandIds.set(name, (await exec(conn, 'INSERT INTO brands (name) VALUES (?)', [name])).insertId)

  for (const [category, group] of Object.entries(PHOTO)) {
    await exec(conn, 'UPDATE categories SET image_url = ? WHERE id = ?', [await photo(conn, `products/${group}-1.jpg`, null), Number(category)])
  }

  const names = new Map(
    (await conn.query<any[]>('SELECT id, name, name_ar FROM categories'))[0].map((c: any) => [c.id as number, [c.name as string, c.name_ar as string]]),
  )
  const thisHour = new Date()
  thisHour.setMinutes(0, 0, 0)

  const count = FIRST.length + MORE.length
  for (let index = 0; index < count; index++) {
    const number = index + 1
    const first = FIRST[index]
    const more = first ? undefined : MORE[index - FIRST.length]!
    const [name, nameAr, categoryKey, brandOrStore, price, original] = first ?? more!
    const sold: Sold = first?.[6] ?? 'plain'
    const store = storeIds.get(first ? (index % 2 === 0 ? 'm-1' : 'm-2') : brandOrStore)!
    const categoryId = CATEGORY[categoryKey]!
    const top = PARENT[categoryId] ?? categoryId
    const stock = index % 7 === 5 ? 0 : 3 + ((index * 5) % 40)
    const created = first ? ago((FIRST.length - index) * 4) : ago(5 + (index - FIRST.length) * 2)
    const status = STATUS[number] ?? 'APPROVED'

    // A demo flash sale is its price, with the price before it as the normal
    // price; any other "originalPrice" is a lasting markdown.
    const onSale = FLASH[number] !== undefined && original !== null && status === 'APPROVED' && !HIDDEN.has(number)
    const base = onSale ? original! : price
    const compareAt = onSale ? null : original
    const saleEnds = onSale ? new Date(thisHour.getTime() + FLASH[number]! * 3_600_000) : null
    const warranty =
      categoryKey === 'c-phone-cases' || price < 20000
        ? null
        : categoryKey === 'c-chargers' || categoryKey === 'c-accessories'
          ? ['6 months manufacturer warranty', 'ضمان الشركة المصنّعة لمدة 6 أشهر']
          : ['12 months manufacturer warranty', 'ضمان الشركة المصنّعة لمدة 12 شهرًا']
    const [catName, catNameAr] = names.get(categoryId)!
    const [topName, topNameAr] = top === categoryId ? ['', ''] : names.get(top)!

    const inserted = await exec(
      conn,
      `INSERT INTO products (store_id, category_id, brand_id, name_en, name_ar, description, description_ar, warranty, warranty_ar,
                             base_price, compare_at_price, sale_price, sale_ends_at, status, rejection_reason, is_active,
                             option_colours, size_guide, submitted_at, search_text, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        store.id,
        categoryId,
        first ? brandIds.get(brandOrStore)! : null,
        name,
        nameAr,
        'Sold and delivered by its store. Pay in cash when it arrives, and return it within 7 days if it is not right.',
        'يبيعه المتجر ويوصله إليك. ادفع نقدًا عند الاستلام، ويمكنك إرجاعه خلال 7 أيام إن لم يكن مناسبًا.',
        warranty?.[0] ?? null,
        warranty?.[1] ?? null,
        base,
        compareAt,
        onSale ? price : null,
        saleEnds,
        status,
        status === 'REJECTED' ? 'Images do not meet the catalogue guidelines.' : null,
        !HIDDEN.has(number),
        sold === 'plain' ? null : JSON.stringify({ Black: '#14181D', Silver: '#C3CAD3', ...(sold === 'phone' && { Blue: '#1A56C4' }) }),
        sold === 'phone'
          ? 'Measurements are taken flat, in centimetres.\n\n128GB - 146 x 71 x 7.6 mm, 172 g\n256GB - 146 x 71 x 7.6 mm, 174 g\n\nIf you are between two options, take the larger one.'
          : null,
        status === 'DRAFT' ? null : created,
        fold([name, nameAr, topName, topNameAr, catName, catNameAr].join(' ')).slice(0, 500),
        created,
      ],
    )
    const productId = inserted.insertId
    await exec(conn, 'INSERT INTO product_images (product_id, url, position) VALUES (?, ?, 0)', [
      productId,
      await photo(conn, `products/${PHOTO[top]}-1.jpg`, store.owner),
    ])

    // MockData._variantsFor: a phone in three colours and two sizes, a laptop in two and two,
    // the larger dearer; the last combination sold out.
    const skus: { options: Record<string, string> | null; price: number | null; stock: number; code: string }[] = []
    if (sold === 'plain') {
      skus.push({ options: null, price: null, stock, code: `SKU-${1000 + index}` })
    } else {
      const colours = sold === 'phone' ? ['Black', 'Silver', 'Blue'] : ['Silver', 'Black']
      const sizes = sold === 'phone' ? ['128GB', '256GB'] : ['512GB', '1TB']
      let n = 0
      for (const colour of colours) {
        for (const size of sizes) {
          const extra = size === sizes.at(-1) ? (sold === 'phone' ? 80000 : 120000) : 0
          const last = colour === colours.at(-1) && size === sizes.at(-1)
          skus.push({ options: { Color: colour, Storage: size }, price: base + extra, stock: last ? 0 : stock, code: `SKU-${1000 + index}-${n++}` })
        }
      }
    }
    for (const sku of skus) {
      const row = await exec(
        conn,
        'INSERT INTO product_skus (product_id, options, option_label, sku_code, price, stock) VALUES (?, ?, ?, ?, ?, ?)',
        [
          productId,
          sku.options === null ? null : JSON.stringify(sku.options),
          sku.options === null ? null : Object.values(sku.options).join(' · '),
          sku.code,
          sku.price,
          sku.stock,
        ],
      )
      if (sku.stock > 0) {
        await exec(conn, "INSERT INTO stock_movements (sku_id, delta, reason) VALUES (?, ?, 'SEEDED')", [row.insertId, sku.stock])
      }
    }
  }

  // Home: every approved demo store on the rail, in the demo's order; the banners.
  let position = 0
  for (const demo of ['m-1', 'm-2', 'm-3', 'm-4', 'm-5', 'm-6', 'm-7', 'm-8']) {
    await exec(conn, 'INSERT INTO featured_stores (store_id, position) VALUES (?, ?)', [storeIds.get(demo)!.id, ++position])
  }
  for (const [i, [title, subtitle, titleAr, subtitleAr]] of BANNERS.entries()) {
    await exec(
      conn,
      'INSERT INTO home_banners (position, title_en, subtitle_en, title_ar, subtitle_ar) VALUES (?, ?, ?, ?, ?)',
      [i + 1, title, subtitle, titleAr, subtitleAr],
    )
  }
  return count
}

const HOUR = 3_600_000
/** A moment on Baghdad's wall clock (UTC+3 all year); months and days overflow as Dart's DateTime does. */
const baghdad = (year: number, month: number, day: number, hour = 0) => new Date(Date.UTC(year, month, day, hour) - 3 * HOUR)
const STEPS = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED'] as const

interface SeedStore {
  demo: string
  id: number
  owner: number
  name: string
  governorate: string
  areas: string[]
  inside: [number, string]
  outside?: [number, string]
}

interface SeedProduct {
  id: number
  name: string
  nameAr: string
  price: number
  store: string
  onSale: boolean
  skuId: number
  skuCode: string | null
  label: string | null
  image: string | null
}

/** The demo stores that sell, and the 56 products, as the catalogue part left them. */
async function loadSeedWorld(conn: Connection): Promise<{ stores: Map<string, SeedStore>; products: SeedProduct[] }> {
  const stores = new Map<string, SeedStore>()
  for (const s of STORES) {
    if (s.status !== 'APPROVED' || !s.delivery) continue
    const row = await one<{ id: number; owner_user_id: number }>(conn, 'SELECT id, owner_user_id FROM stores WHERE store_name = ? AND governorate = ?', [
      s.name,
      s.governorate,
    ])
    if (!row) throw new Error(`${s.name} is missing: the catalogue part must run first.`)
    stores.set(s.demo, {
      demo: s.demo,
      id: row.id,
      owner: row.owner_user_id,
      name: s.name,
      governorate: s.governorate,
      areas: [...new Set([s.governorate, ...s.delivery.areas])],
      inside: s.delivery.inside,
      outside: s.delivery.outside,
    })
  }

  const products: SeedProduct[] = []
  for (let index = 0; index < FIRST.length + MORE.length; index++) {
    const first = FIRST[index]
    const [name, nameAr, , brandOrStore, price] = first ?? MORE[index - FIRST.length]!
    const row = await one<{ id: number }>(conn, 'SELECT id FROM products WHERE name_en = ? AND deleted_at IS NULL', [name])
    if (!row) throw new Error(`${name} is missing: the catalogue part must run first.`)
    const sku = await one<{ id: number; sku_code: string | null; option_label: string | null }>(
      conn,
      'SELECT id, sku_code, option_label FROM product_skus WHERE product_id = ? AND deleted_at IS NULL ORDER BY id LIMIT 1',
      [row.id],
    )
    const image = await one<{ url: string }>(conn, 'SELECT url FROM product_images WHERE product_id = ? ORDER BY position LIMIT 1', [row.id])
    products.push({
      id: row.id,
      name,
      nameAr,
      price,
      store: first ? (index % 2 === 0 ? 'm-1' : 'm-2') : brandOrStore,
      // MockData.startsOnSale: what was bought is only what was for sale.
      onSale: STATUS[index + 1] === undefined && !HIDDEN.has(index + 1),
      skuId: sku!.id,
      skuCode: sku!.sku_code,
      label: sku!.option_label,
      image: image?.url ?? null,
    })
  }
  return { stores, products }
}

interface SeedOrder {
  number: string
  buyer: Customer
  store: SeedStore
  lines: { product: SeedProduct; quantity: number }[]
  placedAt: Date
  status: (typeof STEPS)[number] | 'CANCELLED'
  deliveredAt?: Date
  review?: { stars: number; words: string | null }
  /** Called off before anyone confirmed it: by the shopper (their reason) or the store (its decline code). */
  cancel?: { by: 'SHOPPER' | 'STORE'; reason: string; note?: string; at: Date }
}

/** One seeded order: one store, to [o.buyer]'s city at the store's fee, as far as [o.status]. Returns its id. */
async function insertOrder(conn: Connection, shoppers: Map<string, number>, o: SeedOrder): Promise<number> {
  const [fee, time] = o.buyer.governorate === o.store.governorate ? o.store.inside : o.store.outside!
  const subtotal = o.lines.reduce((sum, line) => sum + line.product.price * line.quantity, 0)
  const units = o.lines.reduce((sum, line) => sum + line.quantity, 0)
  const stage = o.status === 'CANCELLED' ? 0 : STEPS.indexOf(o.status)
  const at = (hours: number) => new Date(o.placedAt.getTime() + hours * HOUR)
  const deliveredAt = o.status === 'DELIVERED' ? (o.deliveredAt ?? at(4)) : null
  const driver = stage >= STEPS.indexOf('SHIPPED') ? DRIVERS[o.store.demo]! : null
  const ratedAt = o.review ? new Date(Math.min(Date.now(), deliveredAt!.getTime() + 24 * HOUR)) : null
  const customerId = shoppers.get(o.buyer.phone)!
  const b = o.buyer
  const c = o.cancel
  const searched = [o.number, b.name, b.nameAr, o.store.name, ...o.lines.flatMap((line) => [line.product.name, line.product.nameAr])]
  const orderId = (
    await exec(
      conn,
      `INSERT INTO orders (order_number, customer_id, status, payment_status, subtotal, discount, shipping, total, item_count,
                           customer_name, customer_name_ar, customer_phone, ship_governorate, ship_area, ship_area_ar, ship_street,
                           ship_street_ar, ship_landmark, ship_landmark_ar, placed_at, delivered_at, rated_at, cancelled_at, cancelled_by,
                           cancel_reason, cancel_note, search_text)
       VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        o.number,
        customerId,
        o.status,
        o.status === 'DELIVERED' ? 'PAID' : o.status === 'CANCELLED' ? 'CANCELLED' : 'PENDING',
        subtotal,
        fee,
        subtotal + fee,
        units,
        b.name,
        b.nameAr,
        b.phone,
        b.governorate,
        b.area,
        b.areaAr,
        b.street,
        b.streetAr,
        b.landmark,
        b.landmarkAr,
        o.placedAt,
        deliveredAt,
        ratedAt,
        c?.at ?? null,
        c?.by ?? null,
        c?.reason ?? null,
        c?.note ?? null,
        fold(searched.join(' ')),
      ],
    )
  ).insertId
  const partId = (
    await exec(
      conn,
      `INSERT INTO order_store_parts (order_id, store_id, status, subtotal, discount, shipping_fee, amount_due, item_count, delivery_time,
                                      courier_name, courier_name_ar, courier_phone, received, confirmed_at, shipped_at, delivered_at,
                                      billing_month, cancellation_reason, cancelled_at, created_at)
       VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        orderId,
        o.store.id,
        o.status,
        subtotal,
        fee,
        subtotal + fee,
        units,
        time,
        driver?.[0] ?? null,
        driver?.[1] ?? null,
        driver?.[2] ?? null,
        o.review ? 1 : null,
        stage >= 1 ? at(1) : null,
        stage >= 3 ? at(3) : null,
        deliveredAt,
        deliveredAt && billingMonth(deliveredAt),
        // Who cancelled a part is its reason: CUSTOMER_CANCELLED is the shopper (Q7).
        c ? (c.by === 'STORE' ? c.reason : 'CUSTOMER_CANCELLED') : null,
        c?.at ?? null,
        o.placedAt,
      ],
    )
  ).insertId
  for (const { product, quantity } of o.lines) {
    await exec(
      conn,
      `INSERT INTO order_items (order_id, part_id, product_id, sku_id, product_name, product_name_ar, variant_label, sku_code, image_url,
                                store_name, unit_price, paid_unit_price, quantity, line_total)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [orderId, partId, product.id, product.skuId, product.name, product.nameAr, product.label, product.skuCode, product.image, o.store.name,
        product.price, product.price, quantity, product.price * quantity],
    )
  }
  await exec(conn, "INSERT INTO order_events (order_id, status, note_code, occurred_at) VALUES (?, 'PENDING', 'ORDER_RECEIVED', ?)", [
    orderId,
    o.placedAt,
  ])
  for (let step = 1; step <= stage; step++) {
    await exec(conn, 'INSERT INTO order_events (order_id, part_id, status, store_name, occurred_at) VALUES (?, ?, ?, ?, ?)', [
      orderId,
      partId,
      STEPS[step],
      o.store.name,
      STEPS[step] === 'DELIVERED' ? deliveredAt : at(step),
    ])
  }
  // A store's decline is its part's step; the shopper's cancel is the whole order's, as the app writes them.
  if (c) {
    await exec(
      conn,
      "INSERT INTO order_events (order_id, part_id, status, reason_code, note, store_name, occurred_at) VALUES (?, ?, 'CANCELLED', ?, ?, ?, ?)",
      [orderId, c.by === 'STORE' ? partId : null, c.reason, c.note ?? null, c.by === 'STORE' ? o.store.name : null, c.at],
    )
  }
  if (o.review) {
    await exec(conn, 'INSERT INTO store_reviews (store_id, order_id, customer_id, rating, body, created_at) VALUES (?, ?, ?, ?, ?, ?)', [
      o.store.id,
      orderId,
      customerId,
      o.review.stars,
      o.review.words,
      ratedAt,
    ])
  }
  return orderId
}

/**
 * S4's records, on a database the catalogue part filled: the stores'
 * shoppers, the demo's three coupons, eight orders of today for each store,
 * the delivered history since the first of the month three months back, and
 * reviews on most of it, which are now each store's rating. Returns [orders, reviews].
 */
async function seedBuying(conn: Connection): Promise<[number, number]> {
  const hash = await hashPassword(PASSWORD)
  const { stores, products } = await loadSeedWorld(conn)

  // The stores' shoppers: an account and a default address each.
  const shoppers = new Map<string, number>()
  for (const c of [...Object.values(CITY_CUSTOMERS), ...HISTORY_CUSTOMERS]) {
    if (shoppers.has(c.phone)) continue
    const id = await account(conn, 'CUSTOMER', c.name, c.phone, null, c.governorate, hash)
    await exec(conn, 'UPDATE users SET full_name_ar = ?, search_text = ? WHERE id = ?', [c.nameAr, userSearchText(c.name, c.nameAr), id])
    await exec(
      conn,
      `INSERT INTO addresses (user_id, label, full_name, full_name_ar, phone, governorate, area, area_ar, street, street_ar, landmark, landmark_ar, is_default)
       VALUES (?, 'Home', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
      [id, c.name, c.nameAr, c.phone, c.governorate, c.area, c.areaAr, c.street, c.streetAr, c.landmark, c.landmarkAr],
    )
    shoppers.set(c.phone, id)
  }

  // `_couponsOf`: today's day on Baghdad's calendar, and a day's last second.
  const local = new Date(Date.now() + 3 * HOUR)
  const [Y, M, D] = [local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()]
  const dayOf = (offset: number) => baghdad(Y, M, D + offset)
  const endOf = (offset: number) => new Date(baghdad(Y, M, D + offset + 1).getTime() - 1000)
  const coupons: [string, string, 'PERCENTAGE' | 'FIXED', number, number | null, Date, Date | null, number | null, number][] = [
    ['m-1', 'NOVA10', 'PERCENTAGE', 10, 100_000, dayOf(-10), endOf(20), 50, 12],
    ['m-1', 'WEEKEND15', 'PERCENTAGE', 15, null, dayOf(3), endOf(5), null, 0],
    ['m-2', 'ATLAS5000', 'FIXED', 5000, 50_000, dayOf(-3), null, 100, 40],
  ]
  for (const [store, code, type, value, minimum, starts, ends, limit, used] of coupons) {
    await exec(
      conn,
      `INSERT INTO coupons (store_id, code, discount_type, value, min_order_amount, starts_at, ends_at, usage_limit, used_count)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [stores.get(store)!.id, code, type, value, minimum, starts, ends, limit, used],
    )
  }

  let orders = 0
  let reviews = 0
  /** One seeded order, counted. */
  async function order(o: SeedOrder): Promise<void> {
    await insertOrder(conn, shoppers, o)
    if (o.review) reviews += 1
    orders += 1
  }

  // `_seedMerchantOrders`: each store's queue today, one order at each step and a few more,
  // to a shopper in its own city and one in another it sends to.
  for (const store of stores.values()) {
    const shelf = products.filter((p) => p.store === store.demo && p.onSale)
    const away = store.areas.find((city) => city !== store.governorate && CITY_CUSTOMERS[city]) ?? store.governorate
    const s = Number(store.demo.slice(2))
    for (let index = 0; index < 8; index++) {
      const lines = []
      for (let line = 0; line < 1 + (index % 3); line++) lines.push({ product: shelf[(index + line) % shelf.length]!, quantity: 1 + (line % 2) })
      const status = STEPS[index % STEPS.length]!
      await order({
        number: `SB-${200000 + 100 * s + index}`,
        buyer: CITY_CUSTOMERS[[store.governorate, away][index % 2]!]!,
        store,
        lines,
        placedAt: new Date(Date.now() - 6 * index * HOUR),
        status,
        ...(status === 'DELIVERED' && { deliveredAt: new Date(Date.now() - (6 * index - 4) * HOUR) }),
      })
    }
  }

  // `_history`: delivered orders from the first of the month three months back
  // until yesterday, numbered across all eight stores by when they were placed.
  const today = baghdad(Y, M, D)
  const sold = Array<number>(8).fill(0)
  const made: { n: number; placedAt: Date; deliveredAt: Date; buyer: Customer; store: SeedStore; lines: { product: SeedProduct; quantity: number }[] }[] = []
  let n = 0
  for (let back = 3; back >= 0; back--) {
    for (let s = 0; s < 8; s++) {
      const store = stores.get(`m-${s + 1}`)!
      const shelf = products.filter((p) => p.store === store.demo && p.onSale)
      const reachable = HISTORY_CUSTOMERS.filter((c) => store.areas.includes(c.governorate))
      for (let k = 0; k < 2 + ((s + back) % 3); k++, n++) {
        const deliveredAt = baghdad(Y, M - back, 3 + k * 8 + (s % 4), 11 + (n % 7))
        if (deliveredAt >= today) continue
        const nth = sold[s]!++
        const lines = []
        for (let line = 0; line < 1 + (n % 2); line++) {
          lines.push({ product: shelf[(nth + line) % shelf.length]!, quantity: line === 0 && n % 3 === 0 ? 2 : 1 })
        }
        made.push({
          n,
          placedAt: new Date(deliveredAt.getTime() - (1 + (n % 3)) * 24 * HOUR),
          deliveredAt,
          buyer: reachable[n % reachable.length]!,
          store,
          lines,
        })
      }
    }
  }
  made.sort((a, b) => a.placedAt.getTime() - b.placedAt.getTime() || a.n - b.n)
  for (const [index, past] of made.entries()) {
    await order({
      number: `SB-${190001 + index}`,
      buyer: past.buyer,
      store: past.store,
      lines: past.lines,
      placedAt: past.placedAt,
      status: 'DELIVERED',
      deliveredAt: past.deliveredAt,
      // Most shoppers rated what came; the stores' ratings are these.
      ...(past.n % 4 !== 3 && { review: { stars: REVIEW_STARS[past.n % REVIEW_STARS.length]!, words: REVIEW_WORDS[past.n % REVIEW_WORDS.length]! } }),
    })
  }
  await exec(
    conn,
    `UPDATE stores s SET rating_sum = (SELECT COALESCE(SUM(r.rating), 0) FROM store_reviews r WHERE r.store_id = s.id),
                         rating_count = (SELECT COUNT(*) FROM store_reviews r WHERE r.store_id = s.id)`,
  )
  return [orders, reviews]
}

/**
 * S5's records, on a database S4's part filled: the web's 8 cancelled orders,
 * a return on every ninth delivered order (in every state), one suspended
 * shopper and one who has not ordered yet. Returns [cancelled, returns].
 */
async function seedAfterSales(conn: Connection): Promise<[number, number]> {
  const { stores, products } = await loadSeedWorld(conn)
  const shoppers = new Map<string, number>()
  for (const c of HISTORY_CUSTOMERS) {
    const row = await one<{ id: number }>(conn, "SELECT id FROM users WHERE phone = ? AND role = 'CUSTOMER'", [c.phone])
    if (!row) throw new Error(`${c.name} is missing: the orders part must run first.`)
    shoppers.set(c.phone, row.id)
  }

  // Called off before anyone confirmed them; numbered apart from the history, SB-180001…
  for (const [i, [demo, who, days, by, reason, note]] of CANCELS.entries()) {
    const shelf = products.filter((p) => p.store === demo && p.onSale)
    const placedAt = new Date(Date.now() - days * DAY - 5 * HOUR)
    await insertOrder(conn, shoppers, {
      number: `SB-${180001 + i}`,
      buyer: HISTORY_CUSTOMERS[who]!,
      store: stores.get(demo)!,
      lines: Array.from({ length: 1 + (i % 2) }, (_, line) => ({ product: shelf[(i * 5 + line) % shelf.length]!, quantity: 1 })),
      placedAt,
      status: 'CANCELLED',
      cancel: { by, reason, ...(note && { note }), at: new Date(placedAt.getTime() + (by === 'STORE' ? 5 : 2) * HOUR) },
    })
  }

  // Every ninth delivered order from the fifth, by when it arrived (the newest
  // placed first on the same moment), returns one of its first line: asked for
  // two days after delivery (an hour ago if that is still to come), answered a
  // day later, refunded three days after it was asked; the fourth declined.
  const delivered = await rows<{ order_id: number; part_id: number; store_id: number; customer_id: number; delivered_at: Date }>(
    conn,
    `SELECT o.id AS order_id, op.id AS part_id, op.store_id, o.customer_id, op.delivered_at
       FROM orders o JOIN order_store_parts op ON op.order_id = o.id
      WHERE op.status = 'DELIVERED' ORDER BY op.delivered_at, o.placed_at DESC, o.id`,
  )
  const now = Date.now()
  let returns = 0
  for (let d = 4, i = 0; d < delivered.length; d += 9, i++) {
    const part = delivered[d]!
    const line = (await one<{ id: number; paid_unit_price: number }>(conn, 'SELECT id, paid_unit_price FROM order_items WHERE part_id = ? ORDER BY id LIMIT 1', [
      part.part_id,
    ]))!
    const asked = part.delivered_at.getTime() + 2 * DAY
    const refundedAt = new Date(asked + 3 * DAY)
    const status = asked > now ? 'REQUESTED' : i === 3 ? 'REJECTED' : refundedAt.getTime() > now ? 'APPROVED' : 'REFUNDED'
    const refunded = status === 'REFUNDED'
    const inserted = await exec(
      conn,
      `INSERT INTO returns (order_id, part_id, store_id, customer_id, status, reason, rejection_reason, refund_amount, requested_at,
                            answered_at, refunded_at, refund_month)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        part.order_id,
        part.part_id,
        part.store_id,
        part.customer_id,
        status,
        RETURN_REASONS[i % RETURN_REASONS.length],
        status === 'REJECTED' ? 'USED' : null,
        line.paid_unit_price,
        new Date(Math.min(asked, now - HOUR)),
        status === 'REQUESTED' ? null : new Date(Math.min(asked + DAY, now - HOUR / 2)),
        refunded ? refundedAt : null,
        refunded ? billingMonth(refundedAt) : null,
      ],
    )
    await exec(conn, 'INSERT INTO return_items (return_id, order_item_id, quantity, refund_amount) VALUES (?, ?, 1, ?)', [
      inserted.insertId,
      line.id,
      line.paid_unit_price,
    ])
    returns += 1
  }

  // Hussein Karim, suspended; Rana Salman, who signed up three days ago.
  await exec(conn, "UPDATE users SET status = 'SUSPENDED', suspension_reason = ? WHERE phone = ? AND role = 'CUSTOMER'", [
    SUSPENDED.reason,
    SUSPENDED.phone,
  ])
  const rana = await account(conn, 'CUSTOMER', RANA.name, RANA.phone, null, RANA.governorate, await hashPassword(PASSWORD))
  await exec(conn, 'UPDATE users SET full_name_ar = ?, search_text = ?, created_at = ? WHERE id = ?', [
    RANA.nameAr,
    userSearchText(RANA.name, RANA.nameAr),
    ago(3),
    rana,
  ])
  await exec(
    conn,
    `INSERT INTO addresses (user_id, label, full_name, full_name_ar, phone, governorate, area, area_ar, street, street_ar, landmark, landmark_ar, is_default)
     VALUES (?, 'Home', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
    [rana, RANA.name, RANA.nameAr, RANA.phone, RANA.governorate, RANA.area, RANA.areaAr, RANA.street, RANA.streetAr, RANA.landmark, RANA.landmarkAr],
  )
  return [CANCELS.length, returns]
}

// S6: the months Saba has marked paid, as the web's demo has them
// (website/src/data/finance.ts): every month before last by every store, a few
// days into the month after; last month by every other store, once that day
// has come. Only a month that owes something can be paid.
async function seedBills(conn: Connection): Promise<number> {
  const { stores } = await loadSeedWorld(conn)
  const admin = await one<{ id: number }>(conn, "SELECT id FROM users WHERE email = 'admin@saba.app' AND role = 'ADMIN'")
  if (!admin) throw new Error("Saba's admin is missing: the catalogue part must run first.")
  const now = new Date()
  const [thisMonth, today] = [billingMonth(now), baghdadDay(now)]
  const last = addMonths(thisMonth, -1)
  let paid = 0
  for (const [s, store] of [...stores.values()].entries()) {
    for (const bill of await storeBills(conn, store.id, now)) {
      if (bill.status !== 'DUE') continue
      const day =
        bill.month < last ? addDays(addMonths(bill.month, 1), 2 + (s % 5)) : bill.month === last && s % 2 === 0 ? addDays(thisMonth, 1 + (s % 4)) : null
      if (day === null || day > today) continue
      await exec(conn, 'INSERT INTO bill_payments (store_id, month, paid_on, owed, rate_percent, recorded_by) VALUES (?, ?, ?, ?, ?, ?)', [
        store.id,
        bill.month,
        day,
        bill.owed,
        COMMISSION_PERCENT,
        admin.id,
      ])
      paid += 1
    }
  }
  return paid
}

// S7: the web's eleven tickets (website/src/data/tickets.ts), from shoppers and
// stores in every status, and the app's chats (`_seedChats`): Amina has asked
// Nova and Atlas something and been answered (Nova's answer still unread), and
// Nova has two shoppers, one still waiting. The demo's second one, "Ali
// Hassan", is not a shopper here: Yousef Karim of Erbil asks instead. The
// demo's "Saba Support" chat has no counterpart (BACKEND_PLAN.md §9 item 11).
type TicketSeed = [
  reference: number,
  opener: { shopper: string } | { store: string },
  category: string,
  status: string,
  subject: string,
  thread: [hoursAgo: number, fromCustomer: boolean, body: string][],
]
const TICKETS: TicketSeed[] = [
  [5001, { shopper: '+9647505550256' }, 'PRODUCT', 'CLOSED', 'Does the Gara air cooler work on 220V?', [
    [480, true, 'Does the Gara Air Cooler 60L work on 220V, and does it need a stabiliser?'],
    [470, false, 'It runs on 220V. The store suggests a stabiliser where the power cuts in and out.'],
  ]],
  [5002, { shopper: '+9647805550167' }, 'ACCOUNT', 'CLOSED', 'لا يصلني رمز التحقق', [
    [340, true, 'أحاول تسجيل الدخول ولا تصلني رسالة الرمز.'],
    [336, false, 'جرّب مرة أخرى الآن، كان هناك تأخير في الرسائل صباح اليوم.'],
    [330, true, 'وصل الرمز، شكراً.'],
  ]],
  [5003, { store: 'Zakho Mobile' }, 'OTHER', 'RESOLVED', 'Can we add a second phone number?', [
    [220, true, 'Our shop has two lines. Can customers see both?'],
    [215, false, 'Not yet: a store shows one phone number. We have noted the request.'],
  ]],
  [5004, { shopper: '+9647705550243' }, 'PAYMENT', 'RESOLVED', 'The driver had no change', [
    [150, true, 'I paid with a 50,000 note for a 35,000 order and the driver had no change. He said the store would send it.'],
    [147, false, 'We have asked the store. They will send the 15,000 with your next order or bring it tomorrow; which do you prefer?'],
    [140, true, 'Tomorrow is fine, thank you.'],
    [120, false, 'The store confirms it was delivered today. We are closing this as resolved.'],
  ]],
  [5005, { store: 'Karbala Tech Point' }, 'ACCOUNT', 'WAITING_FOR_CUSTOMER', 'Why was our store rejected?', [
    [200, true, 'We applied and were rejected. What do we need to change?'],
    [196, false, 'The shop address is missing. Add the street and a landmark in your store details, then apply again, and tell us here when you have.'],
  ]],
  [5006, { shopper: '+9647505550224' }, 'RETURN', 'WAITING_FOR_CUSTOMER', 'The store has not picked up my return', [
    [80, true, 'The store approved my return three days ago but nobody came to collect it.'],
    [75, false, 'Sorry about this. Could you send a photo of the item and the box, so we can pass it to the store?'],
  ]],
  [5007, { store: 'Mosul Appliances' }, 'PRODUCT', 'IN_PROGRESS', 'When will our air fryer be reviewed?', [
    [52, true, 'We sent the Hadba Air Fryer 6L for review four days ago. Is anything missing?'],
    [49, false, 'Thanks for waiting. It is in the queue now; the photos and Arabic name look complete.'],
  ]],
  [5008, { shopper: '+9647805550237' }, 'DELIVERY', 'IN_PROGRESS', 'الطلب تأخر أكثر من أسبوع', [
    [30, true, 'طلبت مكيفاً قبل أسبوع ولم يصل بعد، والمتجر لا يرد على الهاتف.'],
    [26, false, 'نعتذر عن التأخير. تواصلنا مع المتجر وسنعود إليك اليوم بموعد التوصيل.'],
  ]],
  [5009, { store: 'Atlas Home' }, 'PAYMENT', 'OPEN', 'How do we pay last month’s bill?', [
    [6, true, 'Our bill for last month is due. Can we pay in two parts, and where do we send the money?'],
  ]],
  [5010, { shopper: SARA.phone }, 'ORDER', 'OPEN', 'My order still says waiting', [
    [3, true, 'I ordered the Nova X5 this morning (SB-200100) and it still says waiting for the store. Is it coming today?'],
  ]],
  [5011, { store: 'Nova Electronics' }, 'ORDER', 'OPEN', 'A customer refused an order at the door', [
    [2, true, 'Order SB-200103 was refused when our driver arrived. The customer said she ordered by mistake. Do we mark it refused, and who pays our driver?'],
  ]],
]

/** [shopper phone, store, [hours ago, from the store?, words][], has the shopper read it all, has the store]. */
const CHATS: [string, string, [number, boolean, string][], boolean, boolean][] = [
  ['+9647701234567', 'Nova Electronics', [[5, false, 'Hello, when will my order ship?'], [4, true, 'It ships tomorrow morning. Our driver calls before coming.']], false, true],
  ['+9647701234567', 'Atlas Home', [[28, false, 'Can I change the delivery address on my order?'], [27, true, 'Yes, send us the new address and we will change it before it ships.']], true, true],
  [SARA.phone, 'Nova Electronics', [[1, false, 'Is this phone in stock in blue?']], true, false],
  [YOUSEF.phone, 'Nova Electronics', [[20, false, 'Do you deliver to Erbil?'], [19, true, 'Yes, in 3 to 4 days.']], true, true],
]

async function seedTalking(conn: Connection): Promise<[number, number]> {
  const admin = (await one<{ id: number }>(conn, "SELECT id FROM users WHERE email = 'admin@saba.app' AND role = 'ADMIN'"))!
  const storeNamed = async (name: string) =>
    (await one<{ id: number; owner_user_id: number; store_name: string; phone: string }>(
      conn,
      'SELECT s.id, s.owner_user_id, s.store_name, u.phone FROM stores s JOIN users u ON u.id = s.owner_user_id WHERE s.store_name = ?',
      [name],
    )) ?? fail(`${name} is missing: the catalogue part must run first.`)
  const shopperWith = async (phone: string) =>
    (await one<{ id: number; full_name: string; phone: string }>(conn, "SELECT id, full_name, phone FROM users WHERE phone = ? AND role = 'CUSTOMER'", [phone])) ??
    fail(`The shopper ${phone} is missing: the orders part must run first.`)
  const hoursAgo = (hours: number) => ago(0, hours)

  for (const [, opener, category, status, subject, thread] of TICKETS) {
    const [userId, kind, storeId, name, phone] =
      'store' in opener
        ? await storeNamed(opener.store).then((s) => [s.owner_user_id, 'STORE', s.id, s.store_name, s.phone] as const)
        : await shopperWith(opener.shopper).then((u) => [u.id, 'SHOPPER', null, u.full_name, u.phone] as const)
    const [first, last] = [thread[0]!, thread.at(-1)!]
    const inserted = await exec(
      conn,
      `INSERT INTO support_tickets (opened_by_user_id, opened_by_kind, store_id, opener_name, opener_phone, subject, category, status,
                                    last_message, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [userId, kind, storeId, name, phone, subject, category, status, last[2].slice(0, 500), hoursAgo(first[0]), hoursAgo(last[0])],
    )
    await exec(conn, 'UPDATE support_tickets SET reference = ?, updated_at = ? WHERE id = ?', [`T-${5000 + inserted.insertId}`, hoursAgo(last[0]), inserted.insertId])
    for (const [hours, fromCustomer, body] of thread) {
      await exec(conn, 'INSERT INTO support_messages (ticket_id, body, is_from_customer, author_user_id, sent_at) VALUES (?, ?, ?, ?, ?)', [
        inserted.insertId,
        body,
        fromCustomer,
        fromCustomer ? userId : admin.id,
        hoursAgo(hours),
      ])
    }
  }

  for (const [phone, storeName, lines, shopperRead, storeRead] of CHATS) {
    const [shopper, store] = [await shopperWith(phone), await storeNamed(storeName)]
    const chat = await exec(conn, 'INSERT INTO conversations (customer_id, store_id, last_message_at) VALUES (?, ?, ?)', [
      shopper.id,
      store.id,
      hoursAgo(lines.at(-1)![0]),
    ])
    const ids: { id: number; fromStore: boolean }[] = []
    for (const [hours, fromStore, body] of lines) {
      const message = await exec(conn, 'INSERT INTO messages (conversation_id, sender, body, sent_at) VALUES (?, ?, ?, ?)', [
        chat.insertId,
        fromStore ? 'STORE' : 'CUSTOMER',
        body,
        hoursAgo(hours),
      ])
      ids.push({ id: message.insertId, fromStore })
    }
    // Each side has read what it wrote; the rest only when the demo says so.
    const readUpTo = (all: boolean, mine: boolean) => (all ? ids.at(-1)!.id : (ids.filter((m) => m.fromStore === mine).at(-1)?.id ?? null))
    await exec(conn, 'UPDATE conversations SET customer_last_read_id = ?, store_last_read_id = ? WHERE id = ?', [
      readUpTo(shopperRead, false),
      readUpTo(storeRead, true),
      chat.insertId,
    ])
  }
  return [TICKETS.length, CHATS.length]
}

function fail(message: string): never {
  throw new Error(message)
}

const count = async (sql: string) => Number((await one<{ n: number }>(pool, sql))?.n ?? 0)
const hasAmina = async () => (await count("SELECT COUNT(*) AS n FROM users WHERE phone = '+9647701234567'")) === 1

const talkingEmpty = async () =>
  (await count('SELECT COUNT(*) AS n FROM support_tickets')) === 0 && (await count('SELECT COUNT(*) AS n FROM conversations')) === 0
const told = ([tickets, chats]: [number, number]) => `${tickets} tickets, ${chats} chats`

try {
  if ((await count('SELECT COUNT(*) AS n FROM users')) === 0) {
    const [products, [orders, reviews], [cancelled, returns], paid, talking] = await withTransaction(
      pool,
      async (conn) =>
        [await seed(conn), await seedBuying(conn), await seedAfterSales(conn), await seedBills(conn), await seedTalking(conn)] as const,
    )
    console.log(
      `Seeded: ${STORES.length} stores, ${products} products, ${orders + cancelled} orders (${cancelled} cancelled), ${reviews} reviews, ` +
        `${returns} returns, 3 coupons, ${paid} months paid, ${told(talking)}.`,
    )
    console.log(`Every demo account signs in with the password "${PASSWORD}":`)
    console.log('  shopper  Amina Saleh    0770 123 4567  shopper@saba.app')
    console.log('  store    Omar (Nova)    0771 123 4567  merchant@saba.app')
    console.log('  store    Layla (Atlas)  0780 123 4567  merchant2@saba.app')
    console.log('  admin    Saba admin     0770 999 9999  admin@saba.app')
  } else if (
    (await hasAmina()) &&
    (await count('SELECT COUNT(*) AS n FROM orders')) === 0 &&
    (await count('SELECT COUNT(*) AS n FROM coupons')) === 0
  ) {
    // A database seeded before slice 4: slices 4 to 7 are added. Nothing is deleted.
    const [[orders, reviews], [cancelled, returns], paid, talking] = await withTransaction(
      pool,
      async (conn) => [await seedBuying(conn), await seedAfterSales(conn), await seedBills(conn), await seedTalking(conn)] as const,
    )
    console.log(
      `Added to the demo world: ${orders + cancelled} orders (${cancelled} cancelled), ${reviews} reviews, ${returns} returns, 3 coupons, ` +
        `${paid} months paid, ${told(talking)}; the stores' ratings are now their reviews'.`,
    )
  } else if (
    (await hasAmina()) &&
    (await count("SELECT COUNT(*) AS n FROM orders WHERE order_number LIKE 'SB-19%'")) > 0 &&
    (await count("SELECT COUNT(*) AS n FROM orders WHERE order_number LIKE 'SB-18%'")) === 0 &&
    (await count('SELECT COUNT(*) AS n FROM returns')) === 0 &&
    (await count(`SELECT COUNT(*) AS n FROM users WHERE phone = '${RANA.phone}'`)) === 0 &&
    (await talkingEmpty())
  ) {
    // A database seeded in slice 4: slices 5 to 7 are added. Nothing is deleted.
    const [[cancelled, returns], paid, talking] = await withTransaction(
      pool,
      async (conn) => [await seedAfterSales(conn), await seedBills(conn), await seedTalking(conn)] as const,
    )
    console.log(
      `Added to the demo world: ${cancelled} cancelled orders, ${returns} returns, Hussein Karim suspended, Rana Salman, ${paid} months paid, ` +
        `${told(talking)}.`,
    )
  } else if (
    (await hasAmina()) &&
    (await count("SELECT COUNT(*) AS n FROM orders WHERE order_number LIKE 'SB-18%'")) > 0 &&
    (await count(`SELECT COUNT(*) AS n FROM users WHERE phone = '${RANA.phone}'`)) === 1 &&
    (await talkingEmpty())
  ) {
    // A database seeded in slice 5 or 6: the months Saba marked paid (if none are yet) and slice 7 are added. Nothing is deleted.
    const bills = (await count('SELECT COUNT(*) AS n FROM bill_payments')) === 0
    const [paid, talking] = await withTransaction(pool, async (conn) => [bills ? await seedBills(conn) : 0, await seedTalking(conn)] as const)
    console.log(`Added to the demo world: ${bills ? `${paid} months paid, ` : ''}${told(talking)}.`)
  } else {
    console.error(
      'This database already has data; the seed only fills an empty one (or adds the later slices to the demo world) and never deletes anything.\n' +
        'To start over: drop the database, create it empty, then npm run migrate and npm run seed.',
    )
    process.exitCode = 1
  }
} finally {
  await pool.end()
}
