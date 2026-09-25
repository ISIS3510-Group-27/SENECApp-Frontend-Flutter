import '../../core/theme/app_colors.dart';
import '../models/app_notification.dart';
import '../models/campus_event.dart';
import '../models/rso.dart';
import '../models/rso_category.dart';
import '../models/student_profile.dart';

/// Burned data in the front, until we create a backend.
///
/// Everything is seeded in memory for this prototype. No screen builds its own
/// list, so replacing this class with one backed by an HTTP API or a local
/// database later is a change confined to this file (yessir).
class RsoRepository {
  const RsoRepository();

  List<Rso> allRsos() => _rsos;

  Rso byId(int id) => _rsos.firstWhere((r) => r.id == id);

  /// Discover's list, narrowed by the category chip and the search field.
  ///
  /// Search matches name *and* category, so typing "sports" surfaces the whole
  /// category the same way tapping its chip would.
  List<Rso> search({
    RsoCategory category = RsoCategory.all,
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    return _rsos.where((rso) {
      final matchesCategory =
          category == RsoCategory.all || rso.category == category;
      final matchesQuery =
          q.isEmpty ||
          rso.name.toLowerCase().contains(q) ||
          rso.category.label.toLowerCase().contains(q);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  /// Lists three organizations in the Discover carousel.
  List<Rso> featured() => _rsos.take(3).toList();

  List<CampusEvent> allEvents() => _events;

  /// Events hosted by one organization, for its detail screen.
  List<CampusEvent> eventsFor(int rsoId) =>
      _events.where((e) => e.rsoId == rsoId).toList();

  List<AppNotification> allNotifications() => _notifications;

  StudentProfile currentStudent() => _student;

  /// Memberships the student already holds when the app first opens.
  static const seedMembershipIds = {1, 2, 5};

  /// Notifications already read when the app first opens.
  static const seedReadNotificationIds = {4};

  /// Events attended so far this semester. A standalone count because past
  /// attendance is not derivable from the upcoming-events list.
  static const eventsAttended = 11;

  static const currentTerm = 'Sem II';

  /// The date range covered by the Events screen banner.
  static const eventsWeekRange = 'Aug 18 - Aug 24, 2025';

  static const _student = StudentProfile(
    name: 'Sofía Arango',
    email: 's.arango@uniandes.edu.co',
    program: 'Ingeniería de Sistemas · 6to semestre',
    interests: ['Tennis', 'AI/ML', 'Startups', 'Travel', 'Cars'],
    yearsActive: 2,
  );

  static const _rsos = <Rso>[
    Rso(
      id: 1,
      name: 'Tennis Uniandes',
      category: RsoCategory.sports,
      members: 142,
      description:
          'Competitive and recreational tennis for all levels. Weekly matches, '
          'tournaments, and coaching sessions on our campus courts.',
      tags: ['Sports', 'Competitive', 'Outdoor'],
      color: AppColors.primary,
      imageSlug: 'tennis_uniandes',
      nextEvent: 'Sat, Aug 22 · 8:00 AM',
      verified: true,
    ),
    Rso(
      id: 2,
      name: 'Emprendedores Uniandes',
      category: RsoCategory.business,
      members: 318,
      description:
          'Where future founders meet. Pitch nights, mentorship from alumni '
          'VCs, and startup incubation resources for Uniandes students.',
      tags: ['Business', 'Startups', 'Networking'],
      color: AppColors.orange,
      imageSlug: 'emprendedores_uniandes',
      nextEvent: 'Thu, Aug 20 · 6:00 PM',
      verified: true,
    ),
    Rso(
      id: 3,
      name: 'Viajeros Uniandes',
      category: RsoCategory.travel,
      members: 207,
      description:
          'Explore Colombia and beyond. We organize group trips, weekend '
          'getaways, and cultural immersion experiences every semester.',
      tags: ['Travel', 'Adventure', 'Culture'],
      color: AppColors.teal,
      imageSlug: 'viajeros_uniandes',
      nextEvent: 'Fri, Aug 28 · 7:00 AM',
      verified: false,
    ),
    Rso(
      id: 4,
      name: 'Auto Enthusiasts',
      category: RsoCategory.cars,
      members: 89,
      description:
          'Monthly car meets, track days at Tocancipá, and deep dives '
          'into automotive culture. All makes welcome - from classics to '
          'hypercars.',
      tags: ['Cars', 'Community', 'Events'],
      color: AppColors.violet,
      imageSlug: 'auto_enthusiasts',
      nextEvent: 'Sun, Aug 30 · 10:00 AM',
      verified: false,
    ),
    Rso(
      id: 5,
      name: 'AI & Machine Learning',
      category: RsoCategory.technology,
      members: 256,
      description:
          'Research papers, Kaggle competitions, and build sessions. We push '
          'the frontier of AI/ML at Uniandes with weekly workshops.',
      tags: ['Technology', 'Research', 'AI'],
      color: AppColors.blue,
      imageSlug: 'ai_machine_learning',
      nextEvent: 'Wed, Aug 19 · 5:00 PM',
      verified: true,
    ),
    Rso(
      id: 6,
      name: 'Teatro Los Andes',
      category: RsoCategory.arts,
      members: 173,
      description:
          'From improv to full theatrical productions. Auditions are open to '
          'everyone - no experience required, just passion for '
          'storytelling.',
      tags: ['Arts', 'Performance', 'Creative'],
      color: AppColors.pink,
      imageSlug: 'teatro_los_andes',
      nextEvent: 'Tue, Aug 25 · 7:00 PM',
      verified: true,
    ),
    Rso(
      id: 7,
      name: 'Finance Society',
      category: RsoCategory.business,
      members: 195,
      description:
          'CFA prep, Bloomberg terminal access, case competitions, and '
          'connections to top finance firms in Bogotá and beyond.',
      tags: ['Finance', 'Professional', 'Learning'],
      color: AppColors.amber,
      imageSlug: 'finance_society',
      nextEvent: 'Mon, Aug 18 · 5:30 PM',
      verified: false,
    ),
    Rso(
      id: 8,
      name: 'Fotografía Uniandes',
      category: RsoCategory.arts,
      members: 134,
      description:
          'Darkroom access, photowalks around Bogotá, and exhibitions. '
          'Film and digital both welcome.',
      tags: ['Photography', 'Creative', 'Arts'],
      color: AppColors.indigo,
      imageSlug: 'fotografia_uniandes',
      nextEvent: 'Sat, Aug 22 · 2:00 PM',
      verified: false,
    ),
  ];

  static const _events = <CampusEvent>[
    CampusEvent(
      id: 1,
      rsoId: 1,
      rsoName: 'Tennis Uniandes',
      title: 'Round Robin Tournament',
      date: 'Sat, Aug 22',
      time: '8:00 AM',
      location: 'Campus Courts',
      color: AppColors.primary,
    ),
    CampusEvent(
      id: 2,
      rsoId: 5,
      rsoName: 'AI & ML Group',
      title: 'LLM Workshop: Build Your Own Agent',
      date: 'Wed, Aug 19',
      time: '5:00 PM',
      location: 'Edificio SD, Sala 302',
      color: AppColors.blue,
    ),
    CampusEvent(
      id: 3,
      rsoId: 2,
      rsoName: 'Emprendedores Uniandes',
      title: 'Pitch Night #14',
      date: 'Thu, Aug 20',
      time: '6:00 PM',
      location: 'Auditorio Mario Laserna',
      color: AppColors.orange,
    ),
    CampusEvent(
      id: 4,
      rsoId: 3,
      rsoName: 'Viajeros Uniandes',
      title: 'Trip to Salento & Coffee Region',
      date: 'Fri, Aug 28',
      time: '7:00 AM',
      location: 'Meet at Entrada Principal',
      color: AppColors.teal,
    ),
    CampusEvent(
      id: 5,
      rsoId: 4,
      rsoName: 'Auto Enthusiasts',
      title: 'Monthly Car Meet - Agosto',
      date: 'Sun, Aug 30',
      time: '10:00 AM',
      location: 'Parking Lot P6',
      color: AppColors.violet,
    ),
    CampusEvent(
      id: 6,
      rsoId: 6,
      rsoName: 'Teatro Los Andes',
      title: 'Open Auditions: Obra de Semestre',
      date: 'Tue, Aug 25',
      time: '7:00 PM',
      location: 'Teatro Ópera',
      color: AppColors.pink,
    ),
  ];

  static const _notifications = <AppNotification>[
    AppNotification(
      id: 1,
      source: 'Tennis Uniandes',
      message: 'Round Robin Tournament is this Saturday at 8:00 AM.',
      time: '2h ago',
      color: AppColors.primary,
    ),
    AppNotification(
      id: 2,
      source: 'AI & ML Group',
      message: 'New workshop added: LLM Agent Building - Wednesday 5 PM.',
      time: '5h ago',
      color: AppColors.blue,
    ),
    AppNotification(
      id: 3,
      source: 'Emprendedores Uniandes',
      message: 'Pitch Night #14 spots are filling up - reserve yours now.',
      time: '1d ago',
      color: AppColors.orange,
    ),
    AppNotification(
      id: 4,
      source: 'SENECApp',
      message: 'Welcome! You have 3 RSOs that match your interests.',
      time: '2d ago',
      color: AppColors.accent,
    ),
  ];
}
