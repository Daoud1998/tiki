ضع هذه الملفات في نفس المسارات داخل مشروعك (lib/...).

محتويات:
- Home refresh + pull-to-refresh متزامن مع Firestore
- Search يستخدم Firestore (بدون mockProducts) + فلترة wilaya/category محلياً
- Unique views per day: من نفس المستخدم/الجهاز لن يزيد العداد في نفس اليوم
- Promo plans: Boost / Featured / Top + مدد مختلفة (1/3/7/15/30) + نفس الأسعار

ملفات Firestore:
- firestore/promo_plans_seed.json : بيانات الباقات (لنسخها إلى console أو سكربت)
- firestore/promo_rules_snippet.txt : اقتراح Rules للباقات + عداد المشاهدات
- firestore/indexes_promo_and_search.json : اقتراح Indexes (promo + products search)
