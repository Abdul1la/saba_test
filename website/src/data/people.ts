import type { Governorate } from './types'

// The demo's shoppers, with the Arabic the app keeps for them
// (MockApiInterceptor._seedCustomers and _historyCustomers, word for word).
// Orders are placed from here, and Customers lists them. No imports but
// types, so orders.ts and customers.ts can both read it.

export interface Person {
  id: string
  fullName: string
  fullNameAr: string
  phone: string
  governorate: Governorate
  area: string
  areaAr: string
  street: string
  streetAr: string
  landmark: string
  landmarkAr: string
}

/** An account id from the phone: an order keeps the phone, so it finds its shopper. */
export const customerIdOf = (phone: string) => `cu-${phone.replace(/\D/g, '').slice(-7)}`

const person = (p: Omit<Person, 'id'>): Person => ({ id: customerIdOf(p.phone), ...p })

export const SARA = person({
  fullName: 'Sara Ahmed', fullNameAr: 'سارة أحمد', phone: '+9647705550142', governorate: 'BAGHDAD',
  area: 'Karrada', areaAr: 'الكرادة', street: 'Street 62, House 9', streetAr: 'شارع 62، دار 9',
  landmark: 'Behind the Karrada Maternity Hospital', landmarkAr: 'خلف مستشفى الكرادة للولادة',
})

export const YOUSEF = person({
  fullName: 'Yousef Karim', fullNameAr: 'يوسف كريم', phone: '+9647515550198', governorate: 'ERBIL',
  area: 'Ainkawa', areaAr: 'عينكاوا', street: 'Block 3', streetAr: 'بلوك 3',
  landmark: 'Next to Ainkawa Mall', landmarkAr: 'بجانب مول عينكاوا',
})

export const NOOR = person({
  fullName: 'Noor Hadi', fullNameAr: 'نور هادي', phone: '+9647805550167', governorate: 'BASRA',
  area: 'Al-Jazaer', areaAr: 'الجزائر', street: 'Street 20, House 7', streetAr: 'شارع 20، دار 7',
  landmark: 'Near Al-Jazaer Park', landmarkAr: 'قرب متنزه الجزائر',
})

/** The history's shoppers, in the app's order (it picks by index). */
export const HISTORY_PEOPLE: Person[] = [
  SARA,
  YOUSEF,
  NOOR,
  person({
    fullName: 'Ahmed Jasim', fullNameAr: 'أحمد جاسم', phone: '+9647705550211', governorate: 'BAGHDAD',
    area: 'Al-Mansour', areaAr: 'المنصور', street: 'Street 14, House 30', streetAr: 'شارع 14، دار 30',
    landmark: 'Near Al-Rowad Mosque', landmarkAr: 'قرب جامع الرواد',
  }),
  person({
    fullName: 'Hawre Kamal', fullNameAr: 'هاوري كمال', phone: '+9647505550224', governorate: 'SULAYMANIYAH',
    area: 'Bakhtiari', areaAr: 'بختياري', street: 'Street 40, House 12', streetAr: 'شارع 40، دار 12',
    landmark: 'Behind Family Mall', landmarkAr: 'خلف فاميلي مول',
  }),
  person({
    fullName: 'Zahraa Ali', fullNameAr: 'زهراء علي', phone: '+9647805550237', governorate: 'NAJAF',
    area: 'Al-Adala', areaAr: 'العدالة', street: 'Street 9, House 4', streetAr: 'شارع 9، دار 4',
    landmark: 'Near the Kufa University gate', landmarkAr: 'قرب باب جامعة الكوفة',
  }),
  person({
    fullName: 'Omar Farouk', fullNameAr: 'عمر فاروق', phone: '+9647705550243', governorate: 'NINEVEH',
    area: 'Al-Muthanna', areaAr: 'المثنى', street: 'Street 3, House 18', streetAr: 'شارع 3، دار 18',
    landmark: 'Opposite the Al-Muthanna school', landmarkAr: 'مقابل مدرسة المثنى',
  }),
  person({
    fullName: 'Lana Aziz', fullNameAr: 'لانا عزيز', phone: '+9647505550256', governorate: 'DUHOK',
    area: 'Malta', areaAr: 'مالطا', street: 'Street 11, House 6', streetAr: 'شارع 11، دار 6',
    landmark: 'Next to Duhok Gate', landmarkAr: 'بجانب بوابة دهوك',
  }),
  person({
    fullName: 'Mariam Saleh', fullNameAr: 'مريم صالح', phone: '+9647705550262', governorate: 'KIRKUK',
    area: 'Rahimawa', areaAr: 'رحيم آوه', street: 'Street 21, House 9', streetAr: 'شارع 21، دار 9',
    landmark: 'Near the Rahimawa bakery', landmarkAr: 'قرب مخبز رحيم آوه',
  }),
  person({
    fullName: 'Hussein Karim', fullNameAr: 'حسين كريم', phone: '+9647805550278', governorate: 'BABYLON',
    area: 'Al-Jamiaa', areaAr: 'الجامعة', street: 'Street 7, House 25', streetAr: 'شارع 7، دار 25',
    landmark: 'Behind the Hillah courthouse', landmarkAr: 'خلف محكمة الحلة',
  }),
  person({
    fullName: 'Dilshad Omer', fullNameAr: 'دلشاد عمر', phone: '+9647505550283', governorate: 'ERBIL',
    area: 'Italian Village', areaAr: 'القرية الإيطالية', street: 'Villa 44', streetAr: 'فيلا 44',
    landmark: 'Near the village gate', landmarkAr: 'قرب بوابة القرية',
  }),
]
