import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category_model.dart';
import 'business_service.dart';
import 'exceptions.dart';

/// Service providing CRUD operations for product categories.
class CategoryService {
  final SupabaseClient? customClient;
  final BusinessService? customBusinessService;

  CategoryService({
    SupabaseClient? client,
    BusinessService? businessService,
  })  : customClient = client,
        customBusinessService = businessService;

  SupabaseClient get client => customClient ?? Supabase.instance.client;
  BusinessService get businessService =>
      customBusinessService ?? BusinessService(client: customClient);

  /// Fetches all categories for the current user's store business.
  Future<List<Category>> getCategories({String? businessId}) async {
    try {
      final bId = await businessService.getBusinessId();
      final response = await client
          .from('categories')
          .select()
          .eq('business_id', bId)
          .order('name', ascending: true);

      return (response as List<dynamic>)
          .map((json) => Category.fromMap(json as Map<String, dynamic>))
          .toList();
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw CategoryException('Unable to load categories', e);
    }
  }

  /// Creates a new product category under the authenticated user's store business.
  Future<Category> createCategory({
    required String name,
    String? description,
    String? businessId, // Ignored to prevent caller-provided business ID override
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const CategoryException('Category name cannot be empty');
    }

    try {
      final bId = await businessService.getBusinessId();
      final response = await client
          .from('categories')
          .insert({
            'business_id': bId,
            'name': trimmedName,
            'description': (description != null && description.trim().isNotEmpty)
                ? description.trim()
                : null,
          })
          .select()
          .single();

      return Category.fromMap(response);
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw CategoryException('Unable to save category', e);
    }
  }

  /// Updates an existing category belonging to the authenticated user's business.
  Future<Category> updateCategory(Category category) async {
    if (category.name.trim().isEmpty) {
      throw const CategoryException('Category name cannot be empty');
    }
    if (category.id.trim().isEmpty) {
      throw const CategoryException('Category ID is required for update');
    }

    try {
      final bId = await businessService.getBusinessId();
      final response = await client
          .from('categories')
          .update({
            'name': category.name.trim(),
            'description': (category.description != null && category.description!.trim().isNotEmpty)
                ? category.description!.trim()
                : null,
          })
          .eq('id', category.id)
          .eq('business_id', bId)
          .select()
          .single();

      return Category.fromMap(response);
    } on FlexPOSException {
      rethrow;
    } catch (e) {
      throw CategoryException('Unable to update category', e);
    }
  }

  /// Deletes a category belonging to the authenticated user's business.
  Future<void> deleteCategory(String id) async {
    if (id.trim().isEmpty) {
      throw const CategoryException('Category ID is required for deletion');
    }

    try {
      final bId = await businessService.getBusinessId();
      await client
          .from('categories')
          .delete()
          .eq('id', id)
          .eq('business_id', bId);
    } catch (e) {
      throw CategoryException('Unable to delete category', e);
    }
  }
}
