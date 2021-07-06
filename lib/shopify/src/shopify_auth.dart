import 'package:flutter/material.dart';
import 'package:flutter_simple_shopify/mixins/src/shopfiy_error.dart';
import 'package:flutter_simple_shopify/shopify/src/utils/shared_preference_services.dart';
import 'package:graphql/client.dart';
import '../../graphql_operations/mutations/access_token_delete.dart';
import '../../graphql_operations/mutations/customer_access_token_create.dart';
import '../../graphql_operations/mutations/customer_create.dart';
import '../../graphql_operations/mutations/customer_recover.dart';
import '../../graphql_operations/queries/get_customer.dart';
import '../../models/src/shopify_user.dart';
import '../../shopify_config.dart';

/// ShopifyAuth class handles the authentication.
class ShopifyAuth with ShopifyError {
  ShopifyAuth._();
  GraphQLClient get _graphQLClient => ShopifyConfig.graphQLClient;

  static final ShopifyAuth instance = ShopifyAuth._();

  static Map<String, ShopifyUser> _shopifyUser = {};

  @deprecated
  static const String _shopifyKey = 'FLUTTER_SIMPLE_SHOPIFY_ACCESS_TOKEN';

  static Map<String, String> _currentCustomerAccessToken = {};

  static Future<String> get currentCustomerAccessToken async {
    if (_currentCustomerAccessToken.containsKey(ShopifyConfig.storeUrl))
      return _currentCustomerAccessToken[ShopifyConfig.storeUrl];
    final _prefs = await SharedPrefServices.instance;
    if (_prefs.containsKey(ShopifyConfig.storeUrl))
      return _currentCustomerAccessToken[ShopifyConfig.storeUrl] =
          _prefs.getString(ShopifyConfig.storeUrl);
    return _currentCustomerAccessToken[ShopifyConfig.storeUrl] =
        _prefs.getString(_shopifyKey);
  }

  /// Tries to create a new user account with the given email address and password.
  Future<ShopifyUser> createUserWithEmailAndPassword({
    String firstName,
    String lastName,
    @required String email,
    @required String password,
    bool deleteThisPartOfCache = false,
  }) async {
    assert(email != null);
    assert(password != null);
    final MutationOptions _options = MutationOptions(
      document: gql(customerCreateMutation),
      variables: {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
      },
    );
    final QueryResult result = await _graphQLClient.mutate(_options);
    print(result.exception.toString());
    checkForError(
      result,
      key: 'customerCreate',
      errorKey: 'customerUserErrors',
    );
    final shopifyUser = ShopifyUser.fromJson(
        (result?.data['customerCreate'] ?? const {})['customer']);
    final String customerAccessToken = await _createAccessToken(
      email,
      password,
    );
    await _setShopifyUser(
      customerAccessToken,
      _shopifyUser[ShopifyConfig.storeUrl],
    );
    if (deleteThisPartOfCache) {
      _graphQLClient.cache.writeQuery(_options.asRequest, data: null);
    }
    return shopifyUser;
  }

  /// Triggers the Shopify Authentication backend to send a password-reset
  /// email to the given email address, which must correspond to an existing
  /// user of your app.
  Future<void> sendPasswordResetEmail({@required String email, bool deleteThisPartOfCache = false}) async {
    assert(email != null);
    final MutationOptions _options = MutationOptions(
        document: gql(customerRecoverMutation),
        variables: {'email': email});
    final QueryResult result = await _graphQLClient.mutate(_options);
    checkForError(
      result,
      key: 'customerRecover',
      errorKey: 'customerUserErrors',
    );
    if(deleteThisPartOfCache) {
      _graphQLClient.cache.writeQuery(_options.asRequest, data: null);
    }
  }

  /// Tries to sign in a user with the given email address and password.
  Future<ShopifyUser> signInWithEmailAndPassword({
    @required String email,
    @required String password,
    bool deleteThisPartOfCache = false,
  }) async {
    assert(email != null);
    assert(password != null);
    final String customerAccessToken = await _createAccessToken(
      email,
      password,
    );
    final WatchQueryOptions _getCustomer = WatchQueryOptions(
        document: gql(getCustomerQuery),
        variables: {'customerAccessToken': customerAccessToken});
    final QueryResult result = await _graphQLClient.query(_getCustomer);
    checkForError(result);
    final shopifyUser = ShopifyUser.fromJson(result?.data['customer']);
    await _setShopifyUser(customerAccessToken, shopifyUser);
    if (deleteThisPartOfCache) {
      _graphQLClient.cache.writeQuery(_getCustomer.asRequest, data: null);
    }
    return shopifyUser;
  }

  /// Helper method for creating the accessToken.
  Future<String> _createAccessToken(String email, String password, {bool deleteThisPartOfCache = false}) async {
    final MutationOptions _options = MutationOptions(
        document: gql(customerAccessTokenCreate),
        variables: {'email': email, 'password': password});
    final QueryResult result = await _graphQLClient.mutate(_options);
    if(deleteThisPartOfCache) {
      _graphQLClient.cache.writeQuery(_options.asRequest, data: null);
    }
    return _extractAccessToken(result?.data);
  }

  /// Helper method for extracting the customerAccessToken from the mutation.
  String _extractAccessToken(Map<String, dynamic> mutationData) {
    return (((mutationData ?? const {})['customerAccessTokenCreate'] ?? const {})['customerAccessToken'] ?? const {})
    ['accessToken'];
  }

  /// Signs out the current user and clears it from the disk cache.
  Future<void> signOutCurrentUser({bool deleteThisPartOfCache = false}) async {
    final MutationOptions _options = MutationOptions(
        document: gql(accessTokenDeleteMutation),
        variables: {'customerAccessToken': await currentCustomerAccessToken});
    await _setShopifyUser(null, null);
    final QueryResult result = await _graphQLClient.mutate(_options);
    checkForError(
      result,
      key: 'customerAccessTokenDelete',
      errorKey: 'userErrors',
    );
    if(deleteThisPartOfCache) {
      _graphQLClient.cache.writeQuery(_options.asRequest, data: null);
    }
    return result;
  }

  /// Returns the currently signed-in [ShopifyUser] or [null] if there is none.
  Future<ShopifyUser> currentUser({bool deleteThisPartOfCache = false}) async {
    final WatchQueryOptions _getCustomer = WatchQueryOptions(
        document: gql(getCustomerQuery),
        variables: {'customerAccessToken': await currentCustomerAccessToken});
    if (deleteThisPartOfCache) {
      _graphQLClient.cache.writeQuery(_getCustomer.asRequest, data: null);
    }
    if (_shopifyUser.containsKey(ShopifyConfig.storeUrl)) {
      return _shopifyUser[ShopifyConfig.storeUrl];
      //TODO look into shared prefs (@adam)
    } else if (await currentCustomerAccessToken != null) {
      final QueryResult result = (await _graphQLClient.query(_getCustomer));
      checkForError(result);
      ShopifyUser user = ShopifyUser.fromJson(
          (result?.data ?? const {})['customer'] ?? const {});
      return user;
    } else {
      return null;
    }
  }

  Future<void> _setShopifyUser(
    String sharedPrefsToken,
    ShopifyUser shopifyUser,
  ) async {
    var _prefs = await SharedPrefServices.instance;
    if (sharedPrefsToken == null) {
      _shopifyUser.remove(ShopifyConfig.storeUrl);
      _currentCustomerAccessToken.remove(ShopifyConfig.storeUrl);
      _prefs.remove(_shopifyKey);
      _prefs.remove(ShopifyConfig.storeUrl);
    } else {
      _shopifyUser[ShopifyConfig.storeUrl] = shopifyUser;
      _currentCustomerAccessToken[ShopifyConfig.storeUrl] = sharedPrefsToken;
      _prefs.setString(ShopifyConfig.storeUrl, sharedPrefsToken);
    }
  }
}
