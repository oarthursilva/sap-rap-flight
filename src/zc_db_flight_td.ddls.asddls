@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@EndUserText.label: 'Projection View for ZI_DB_FLIGHT_TD'
@ObjectModel.semanticKey: [ 'TravelID' ]
@Search.searchable: true
define root view entity ZC_DB_FLIGHT_TD
  provider contract transactional_query
  as projection on ZI_DB_FLIGHT_TD
{
      @Search.defaultSearchElement: true
      @Search.fuzzinessThreshold: 0.9
  key TravelID,

      @Search.defaultSearchElement: true
      @ObjectModel.text.element: [ 'AgencyName' ]
      @Consumption.valueHelpDefinition: [{
        entity: {
            name: '/DMO/I_Agency',
            element: 'AgencyID'
        },
        useForValidation: true
      }]
      AgencyID,
      _Agency.Name              as AgencyName,

      @Search.defaultSearchElement: true
      @ObjectModel.text.element: [ 'CustomerName' ]
      @Consumption.valueHelpDefinition: [{
        entity: {
            name: '/DMO/I_Customer',
            element: 'CustomerID'
        },
        useForValidation: true
      }]
      CustomerID,
      _Customer.LastName        as CustomerName,

      BeginDate,
      EndDate,
      BookingFee,
      TotalPrice,

      @Consumption.valueHelpDefinition: [{
        entity: {
            name: 'I_Currency',
            element: 'Currency'
        },
        useForValidation: true
      }]
      CurrencyCode,
      Description,

      @ObjectModel.text.element: [ 'OverallStatusText' ]
      @Consumption.valueHelpDefinition: [{
        entity: {
            name: '/DMO/I_Overall_Status_VH',
            element: 'OverallStatus'
        },
        useForValidation: true
      }]
      OverallStatus,
      _OverallStatus._Text.Text as OverallStatusText : localized,

      Attachment,
      MimeType,
      FileName,
      LocalLastChangeAt

}
