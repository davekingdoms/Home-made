import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';

/// Location (A11): the last step of the first start, once per device. A
/// placeholder outside the startup gate until PR 4.8.
RouteBase locationRoute() => placeholderRoute('A11', path: '/location');
