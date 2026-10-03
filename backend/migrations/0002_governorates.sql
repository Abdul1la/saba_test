-- Iraq's 19 governorates, in the app's order (mobile/lib/core/location/governorate.dart),
-- with its English and Arabic names. /stores/cities answers in sort_order.

INSERT INTO governorates (code, name_en, name_ar, sort_order) VALUES
  ('BAGHDAD',      'Baghdad',               'بغداد',               1),
  ('BASRA',        'Basra',                 'البصرة',              2),
  ('NINEVEH',      'Nineveh (Mosul)',       'نينوى (الموصل)',      3),
  ('ERBIL',        'Erbil',                 'أربيل',               4),
  ('SULAYMANIYAH', 'Sulaymaniyah',          'السليمانية',          5),
  ('DUHOK',        'Duhok',                 'دهوك',                6),
  ('KIRKUK',       'Kirkuk',                'كركوك',               7),
  ('NAJAF',        'Najaf',                 'النجف',               8),
  ('KARBALA',      'Karbala',               'كربلاء',              9),
  ('BABYLON',      'Babylon (Hillah)',      'بابل (الحلة)',        10),
  ('ANBAR',        'Anbar (Ramadi)',        'الأنبار (الرمادي)',   11),
  ('DHI_QAR',      'Dhi Qar (Nasiriyah)',   'ذي قار (الناصرية)',   12),
  ('DIYALA',       'Diyala (Baqubah)',      'ديالى (بعقوبة)',      13),
  ('SALAH_AL_DIN', 'Salah al-Din (Tikrit)', 'صلاح الدين (تكريت)',  14),
  ('WASIT',        'Wasit (Kut)',           'واسط (الكوت)',        15),
  ('MAYSAN',       'Maysan (Amarah)',       'ميسان (العمارة)',     16),
  ('QADISIYAH',    'Qadisiyah (Diwaniyah)', 'القادسية (الديوانية)', 17),
  ('MUTHANNA',     'Muthanna (Samawah)',    'المثنى (السماوة)',    18),
  ('HALABJA',      'Halabja',               'حلبجة',               19);
