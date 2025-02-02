const String getProductByHandle = r'''
query getProductByHandle($handle : String!){
  productByHandle(handle: $handle) {
    id
    handle
    images(first: 250) {
      edges {
        node {
          url
        }
      }
    }
    variants(first: 250) {
      edges {
        node {
          priceV2 {
            amount
            currencyCode
          }
          quantityAvailable
        }
      }
    }
  }
}
''';