import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/context_extensions.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/saba_nav_bar.dart';

/// Saba's three rule pages. Written in the app for version 1; the web admin
/// will serve them once it exists, so they can change without a release.
///
/// Every rule here is one the app enforces: 7 days to return, cash back from
/// the store, cancel until the store starts preparing, 1,000,000 IQD on a
/// first order, 8% a month for stores. Change one and change the page.
///
/// Plain words, not a lawyer's. Have a lawyer in Iraq read them before
/// launch.
///
/// The Privacy policy is `backend/public/privacy.html` word for word, blanks
/// included (DEPLOYMENT.md §6); `legal_pages_test` holds them together.
enum LegalPage {
  terms('terms'),
  privacy('privacy'),
  returns('returns');

  const LegalPage(this.slug);

  final String slug;

  String title(AppLocalizations l10n) => switch (this) {
    LegalPage.terms => l10n.termsOfUse,
    LegalPage.privacy => l10n.privacyPolicy,
    LegalPage.returns => l10n.returnPolicy,
  };

  static LegalPage? fromSlug(String? slug) {
    for (final page in values) {
      if (page.slug == slug) return page;
    }
    return null;
  }

  /// A heading and its paragraphs, one per line, in [languageCode]. An empty
  /// heading opens the page with no heading of its own.
  List<(String, String)> sectionsIn(String languageCode) =>
      (languageCode == 'ar' ? _arabic : _english)[this]!;
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.page});

  final LegalPage page;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = page.sectionsIn(
      Localizations.localeOf(context).languageCode,
    );

    return Scaffold(
      appBar: SabaAppBar(title: page.title(l10n)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          SabaNavBar.clearance(context),
        ),
        children: [
          // A readable measure: on a tablet the lines ran the full width.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Metadata, so quiet.
                  Text(
                    l10n.legalUpdated,
                    style: context.textStyles.labelSmall?.copyWith(
                      color: context.market.textMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  for (final (index, (heading, body)) in sections.indexed) ...[
                    SizedBox(
                      height: index == 0 ? AppSpacing.xl : AppSpacing.xxl + 4,
                    ),
                    if (heading.isNotEmpty) ...[
                      Text(
                        heading,
                        style: AppTypography.subsectionTitle(context),
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                    ],
                    for (final (at, paragraph) in body.split('\n').indexed) ...[
                      if (at > 0) const SizedBox(height: AppSpacing.md),
                      Text(
                        paragraph,
                        style: context.textStyles.bodyMedium?.copyWith(
                          fontSize: 15,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rule pages as links side by side, for a sign-up form and for someone
/// not signed in: the rules are agreed to before there is an account.
class LegalLinks extends StatelessWidget {
  const LegalLinks({
    super.key,
    this.note,
    this.pages = const [LegalPage.terms, LegalPage.privacy],
  });

  /// A line above the links, such as "By creating an account you agree to".
  final String? note;

  final List<LegalPage> pages;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget link(LegalPage page) => TextButton(
      onPressed: () => context.push(AppRoutes.legalPath(page.slug)),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, AppSizes.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: Text(page.title(l10n)),
    );

    return Column(
      children: [
        if (note != null)
          Text(
            note!,
            textAlign: TextAlign.center,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        // A Wrap, so a large text size puts the second link on its own line
        // instead of past the edge.
        Wrap(
          alignment: WrapAlignment.center,
          children: [for (final page in pages) link(page)],
        ),
      ],
    );
  }
}

const Map<LegalPage, List<(String, String)>> _english = {
  LegalPage.terms: [
    (
      'What Saba is',
      'Saba is a marketplace in Iraq. Stores sell their own products on '
          'Saba; Saba is not the seller. Each store is responsible for what '
          'it sells, its prices and its delivery.',
    ),
    (
      'Your account',
      'You sign up with your Iraqi mobile number and a password. You must '
          'be 18 or older. Keep your password to yourself: whatever is done '
          'with your account is done by you.',
    ),
    (
      'Ordering and paying',
      'Prices are in Iraqi dinars. You pay in cash when your order arrives. '
          'Each store delivers its own part of an order, with its own driver '
          'or a delivery company, and you pay each driver for their store\'s '
          'part. A first order can be up to 1,000,000 IQD; the limit goes '
          'once one order has been delivered and paid.',
    ),
    (
      'Cancelling',
      'You can cancel an order until the store starts preparing it. After '
          'that, you can refuse it at the door, or return it.',
    ),
    (
      'Returns',
      'You have 7 days after delivery to return an item, and the store '
          'hands your money back in cash. The Return policy page explains '
          'how.',
    ),
    (
      'Stores',
      'A store sells on Saba once Saba has approved it. It must describe '
          'its products truthfully, in Arabic as well, deliver what was '
          'ordered, and take back returns within the 7 days. Saba\'s share '
          'is 8% of a store\'s delivered sales, less the cash it handed back '
          'on returns, billed once a month. A store that deletes its account '
          'still finishes the orders, returns and bill it has open.',
    ),
    (
      'Not allowed',
      'Anything illegal in Iraq; fake, stolen or dangerous goods; weapons '
          'and drugs; misleading a shopper or a store; and using someone '
          'else\'s details. Saba may remove a product or suspend an account '
          'that does any of these.',
    ),
    (
      // Apple 1.2: there are reviews and chats.
      'Reviews, messages and reports',
      'Saba has zero tolerance for objectionable content and abusive users. '
          'Do not post or send anything insulting, hateful, sexual or '
          'threatening, in a review or a message.\n'
          'You can report a review, a product, a store or a chat, and block a '
          'chat. Saba acts on reports quickly: it removes what breaks these '
          'rules, and removes the accounts of users who abuse others.',
    ),
    (
      'Changes and contact',
      'When these terms change, the app tells you before the change '
          'applies. You can delete your account at any time: in Account, tap '
          'your name (or My profile, if you own a store), then choose Delete '
          'account. The Privacy policy says what is deleted and what is kept. '
          'Questions go to Support, in Account.',
    ),
  ],
  LegalPage.privacy: [
    (
      '',
      'Saba is an online marketplace in Iraq, run by {{COMPANY_NAME_EN}}. '
          'This page says what Saba keeps about you, why, and who sees it.',
    ),
    (
      'What Saba keeps',
      'Your name, mobile number, governorate and delivery addresses. Your '
          'orders, returns, reviews and messages with stores and Support. For '
          'a store, also its details and its owner\'s contact.\n'
          'Saba gets these details from you when you use the app. It also '
          'keeps the reports you send, the internet (IP) address your phone '
          'connects from, and your phone\'s notification ID.\n'
          'A photo you send in a chat is seen only by the other side of that '
          'chat, and by Saba if the chat is reported. It is kept privately, '
          'without the place where it was taken.',
    ),
    (
      'Why',
      'To run your account, get your orders to you, handle returns and '
          'questions, and keep Saba safe from fraud.',
    ),
    (
      'Who sees it',
      'The store you order from sees your name, mobile number and delivery '
          'address, so it can call you and deliver. Its driver or delivery '
          'company gets what they need to find you. Saba does not sell your '
          'details to anyone.\n'
          'A store you message sees your name, and your reviews show to '
          'everyone on Saba with your first name and the first letter of your '
          'last name.',
    ),
    (
      'Services that help run Saba',
      'Saba uses these services. Each gets only what its job needs, and must '
          'protect it at least as well as this policy says.\n'
          'OTPIQ sends Saba\'s SMS messages, such as your sign-up code, so it '
          'gets your mobile number and the message.\n'
          'Google Firebase delivers the app\'s notifications to your phone '
          '(to an iPhone, through Apple\'s service), so it gets your phone\'s '
          'notification ID and the notification\'s text.\n'
          'DigitalOcean hosts Saba\'s server, database and photos, so your '
          'details are stored on its computers.',
    ),
    (
      'Paying',
      'You pay in cash. Saba asks for no card and keeps no card details.',
    ),
    (
      'Keeping your details safe',
      'The app talks to Saba\'s server only over an encrypted connection '
          '(HTTPS), and Saba never keeps your password itself, only a '
          'scrambled form of it.',
    ),
    ('Your choices', 'You can see and change your details in Account.'),
    (
      'Deleting your account',
      'In Account, tap your name (or My profile, if you own a store), then '
          'choose Delete account. You can also ask without the app, on the '
          'Delete your Saba account page of Saba\'s website.\n'
          'A shopper\'s account is deleted at once, once none of its orders '
          'is still open. A store closes as soon as it asks. Its account is '
          'deleted once its open orders and returns are finished, the return '
          'window (7 days after its last delivery) has passed, and its last '
          'bill, due when the month ends, is paid; Saba sends an SMS when it '
          'is done. While a bill is unpaid, the store stays closed and its '
          'account is not deleted, and Saba keeps the owner\'s number to '
          'collect it.\n'
          'Your name, number, saved addresses, cart, wishlist and phone\'s '
          'notification ID are deleted. A shopper\'s reviews and messages '
          'stay, without the name. The photos you sent in chats are deleted; '
          'one in a report Saba is still looking at is deleted once Saba '
          'closes the report. A store\'s page and products go; its messages '
          'keep the store\'s name, as its orders do. Orders, invoices, '
          'returns and bills are kept as long as the law requires, for tax '
          'and disputes, with the name, number and address each order was '
          'delivered to. A store\'s name, and what it sold, stay on them. '
          'Saba keeps these records for {{RECORDS_KEPT_EN}}.',
    ),
    (
      'Staying safe',
      'Saba will never ask for your password or the SMS code in a call or a '
          'message. Anyone who does is not Saba.',
    ),
    (
      'Questions',
      'Questions about your details or this policy go to Support, in Account, '
          'or to Saba on WhatsApp at +{{WHATSAPP}} or by email to '
          '{{SUPPORT_EMAIL}}.',
    ),
  ],
  LegalPage.returns: [
    (
      '7 days, at every store',
      'You can return an item within 7 days after it is delivered. The rule '
          'is the same at every store on Saba.',
    ),
    (
      'How',
      'Open the order in Orders and choose Return. Pick the items and say '
          'why. Items from one store go back together; another store\'s '
          'items are a separate return.',
    ),
    (
      'What happens next',
      'The store approves or declines. If it approves, it collects the item '
          'and hands your money back in cash. Each step shows on the return '
          'in the app.',
    ),
    (
      'The item',
      'Send it back as it came, with its box and everything that was in it. '
          'A store may decline an item that is damaged or incomplete.',
    ),
    (
      'Something wrong on delivery',
      'If your order did not come, answer No to "Did you receive it?" on '
          'the order, and the store will call you. If you and a store cannot '
          'agree, contact Support.',
    ),
  ],
};

const Map<LegalPage, List<(String, String)>> _arabic = {
  LegalPage.terms: [
    (
      'ما هي سبأ',
      'سبأ سوق إلكتروني في العراق. تبيع المتاجر منتجاتها على سبأ، وسبأ ليست '
          'البائع. كل متجر مسؤول عمّا يبيعه وعن أسعاره وعن توصيله.',
    ),
    (
      'حسابك',
      'تسجّل برقم هاتفك العراقي وكلمة مرور. يجب '
          'أن يكون عمرك 18 سنة أو أكثر. لا تعطِ كلمة مرورك لأحد: كل ما يُفعل '
          'بحسابك يُحسب عليك.',
    ),
    (
      'الطلب والدفع',
      'الأسعار بالدينار العراقي. تدفع نقداً عند وصول طلبك. كل متجر يوصل '
          'جزءه من الطلب بسائقه أو بشركة توصيل، وتدفع لكل سائق ثمن جزء متجره. '
          'يمكن أن يصل أول طلب إلى 1,000,000 د.ع، ويُرفع هذا الحد بعد توصيل '
          'طلب واحد ودفعه.',
    ),
    (
      'الإلغاء',
      'يمكنك إلغاء الطلب حتى يبدأ المتجر بتجهيزه. بعد ذلك يمكنك رفضه عند '
          'الباب أو إرجاعه.',
    ),
    (
      'الإرجاع',
      'لديك 7 أيام بعد التوصيل لإرجاع أي منتج، ويعيد لك المتجر مالك نقداً. '
          'صفحة سياسة الإرجاع تشرح الطريقة.',
    ),
    (
      'المتاجر',
      'يبيع المتجر على سبأ بعد موافقة سبأ عليه. عليه أن يصف منتجاته بصدق، '
          'وبالعربية أيضاً، وأن يوصل ما طُلب، وأن يقبل الإرجاع خلال الأيام '
          'السبعة. حصة سبأ 8% من مبيعات المتجر المسلّمة، بعد خصم المبالغ التي '
          'أعادها نقداً عن المرتجعات، وتُحسب مرة كل شهر. والمتجر الذي يحذف '
          'حسابه يُكمل ما لديه من طلبات ومرتجعات وآخر فاتورة.',
    ),
    (
      'غير مسموح',
      'كل ما يخالف القانون في العراق، والبضائع المقلّدة أو المسروقة أو '
          'الخطرة، والأسلحة والمخدرات، وخداع أي مشترٍ أو متجر، واستخدام بيانات '
          'شخص آخر. يمكن لسبأ حذف أي منتج أو إيقاف أي حساب يفعل ذلك.',
    ),
    (
      'التقييمات والرسائل والبلاغات',
      'لا تتسامح سبأ مطلقاً مع المحتوى المسيء ولا مع المستخدمين المسيئين. لا '
          'تنشر ولا ترسل أي شتيمة أو كراهية أو محتوى جنسي أو تهديد، في تقييم '
          'أو رسالة.\n'
          'يمكنك الإبلاغ عن تقييم أو منتج أو متجر أو محادثة، وحظر أي محادثة. '
          'وتتعامل سبأ مع البلاغات بسرعة: تحذف ما يخالف هذه القواعد، وتحذف '
          'حسابات من يسيئون إلى غيرهم.',
    ),
    (
      'التغييرات والتواصل',
      'عندما تتغير هذه الشروط يخبرك التطبيق قبل أن يبدأ العمل بها. يمكنك '
          'حذف حسابك في أي وقت: من «حسابي» اضغط على اسمك (أو على «ملفي '
          'الشخصي» إن كنت صاحب متجر)، ثم اختر «حذف الحساب». وتبيّن سياسة '
          'الخصوصية ما يُحذف وما يُحفظ. أرسل أسئلتك إلى الدعم من «حسابي».',
    ),
  ],
  LegalPage.privacy: [
    (
      '',
      'سبأ سوق إلكتروني في العراق، والجهة التي تديره {{COMPANY_NAME_AR}}. '
          'تبيّن هذه الصفحة ما تحفظه سبأ عنك، ولماذا، ومن يراه.',
    ),
    (
      'ما تحفظه سبأ',
      'اسمك ورقم هاتفك ومحافظتك وعناوين التوصيل. طلباتك ومرتجعاتك وتقييماتك '
          'ورسائلك مع المتاجر والدعم. وللمتجر أيضاً بياناته ووسيلة التواصل مع '
          'صاحبه.\n'
          'تحصل سبأ على هذه البيانات منك حين تستخدم التطبيق. وتحفظ أيضاً '
          'البلاغات التي ترسلها، وعنوان الإنترنت (IP) الذي يتصل منه هاتفك، '
          'ومعرّف الإشعارات الخاص بهاتفك.\n'
          'الصورة التي ترسلها في محادثة لا يراها إلا الطرف الآخر في تلك '
          'المحادثة، وسبأ إذا أُبلغ عن المحادثة. وتُحفظ بشكل خاص، دون المكان '
          'الذي التُقطت فيه.',
    ),
    (
      'لماذا',
      'لتشغيل حسابك وإيصال طلباتك إليك ومتابعة المرتجعات والأسئلة وحماية سبأ '
          'من الاحتيال.',
    ),
    (
      'من يرى بياناتك',
      'المتجر الذي تطلب منه يرى اسمك ورقم هاتفك وعنوان التوصيل ليتصل بك ويوصل '
          'طلبك. وسائقه أو شركة التوصيل يحصلون على ما يلزم للوصول إليك. سبأ '
          'لا تبيع بياناتك لأي أحد.\n'
          'والمتجر الذي تراسله يرى اسمك، وتظهر تقييماتك للجميع على سبأ مع '
          'اسمك الأول والحرف الأول من اسمك الأخير.',
    ),
    (
      'خدمات تساعد في تشغيل سبأ',
      'تستخدم سبأ هذه الخدمات. لا تحصل كل خدمة منها إلا على ما يلزم لعملها، '
          'وعليها أن تحميه حمايةً لا تقلّ عمّا تنص عليه هذه السياسة.\n'
          'OTPIQ ترسل رسائل سبأ النصية، مثل رمز التسجيل، فتحصل على رقم هاتفك '
          'ونص الرسالة.\n'
          'Google Firebase توصل إشعارات التطبيق إلى هاتفك (وإلى الآيفون عبر '
          'خدمة آبل)، فتحصل على معرّف الإشعارات الخاص بهاتفك ونص الإشعار.\n'
          'DigitalOcean تستضيف خادم سبأ وقاعدة بياناتها وصورها، فتُحفظ '
          'بياناتك على أجهزتها.',
    ),
    ('الدفع', 'تدفع نقداً. سبأ لا تطلب أي بطاقة ولا تحفظ بيانات بطاقات.'),
    (
      'حماية بياناتك',
      'لا يتصل التطبيق بخادم سبأ إلا عبر اتصال مشفّر (HTTPS)، ولا تحفظ سبأ '
          'كلمة مرورك نفسها، بل صيغة مشفّرة منها فقط.',
    ),
    ('خياراتك', 'يمكنك رؤية بياناتك وتعديلها من حسابي.'),
    (
      'حذف حسابك',
      'من حسابي اضغط على اسمك (أو على ملفي الشخصي إن كنت صاحب متجر)، ثم اختر '
          'حذف الحساب. ويمكنك أن تطلب الحذف من دون التطبيق، من صفحة حذف حسابك '
          'في سبأ على موقع سبأ.\n'
          'يُحذف حساب المتسوق فوراً، ما دام لا يوجد له طلب مفتوح. ويُغلق '
          'المتجر فور طلبه، ويُحذف حسابه بعد أن تنتهي طلباته المفتوحة '
          'ومرتجعاته، وتمضي مدة الإرجاع (7 أيام بعد آخر توصيل)، وتُدفع آخر '
          'فاتورة له، وهي تُستحق عند نهاية الشهر، وترسل سبأ رسالة نصية عند '
          'اكتمال الحذف. وما دامت فاتورة غير مدفوعة يبقى المتجر مغلقاً ولا '
          'يُحذف حسابه، وتحتفظ سبأ برقم صاحبه لتحصيلها.\n'
          'يُحذف اسمك ورقمك وعناوينك المحفوظة والسلة والمفضلة ومعرّف '
          'الإشعارات الخاص بهاتفك. تبقى تقييمات المتسوق ورسائله دون اسمه. '
          'وتُحذف الصور التي أرسلتها في المحادثات؛ والصورة الموجودة في بلاغ '
          'ما زالت سبأ تنظر فيه تُحذف حين تُغلق سبأ البلاغ. وتُحذف صفحة '
          'المتجر ومنتجاته، وتبقى رسائله باسم المتجر كما تبقى طلباته. تُحفظ '
          'الطلبات والفواتير والمرتجعات وفواتير سبأ الشهرية المدة التي يفرضها '
          'القانون، للضرائب والنزاعات، ومعها الاسم والرقم والعنوان الذي وصل '
          'إليه كل طلب. ويبقى عليها اسم المتجر وما باعه. وتحتفظ سبأ بهذه '
          'السجلات {{RECORDS_KEPT_AR}}.',
    ),
    (
      'احمِ نفسك',
      'لن تطلب منك سبأ أبداً كلمة المرور أو رمز الرسالة في اتصال أو رسالة. من '
          'يطلبها ليس سبأ.',
    ),
    (
      'أسئلتك',
      'أرسل أسئلتك عن بياناتك أو عن هذه السياسة إلى الدعم من حسابي، أو راسل '
          'سبأ على واتساب \u2066+{{WHATSAPP}}\u2069 أو بالبريد الإلكتروني على '
          '{{SUPPORT_EMAIL}}.',
    ),
  ],
  LegalPage.returns: [
    (
      '7 أيام، في كل المتاجر',
      'يمكنك إرجاع أي منتج خلال 7 أيام بعد توصيله. القاعدة واحدة في كل '
          'متاجر سبأ.',
    ),
    (
      'الطريقة',
      'افتح الطلب من صفحة الطلبات واختر إرجاع. حدّد المنتجات واذكر السبب. '
          'منتجات المتجر الواحد تُرجع معاً، ومنتجات متجر آخر إرجاع منفصل.',
    ),
    (
      'ماذا يحدث بعد ذلك',
      'يوافق المتجر أو يرفض. إذا وافق يستلم المنتج ويعيد لك مالك نقداً. '
          'تظهر كل خطوة على طلب الإرجاع في التطبيق.',
    ),
    (
      'المنتج',
      'أرجعه كما وصلك، مع علبته وكل ما كان فيها. يمكن للمتجر رفض منتج تالف '
          'أو ناقص.',
    ),
    (
      'مشكلة في التوصيل',
      'إذا لم يصلك الطلب فأجب بـ«لا» على سؤال «هل استلمته؟» في صفحة الطلب، '
          'وسيتصل بك المتجر. وإذا لم تتفق مع المتجر فتواصل مع الدعم.',
    ),
  ],
};
