CLASS lhc_traveldata DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    CONSTANTS BEGIN OF travel_status.
    CONSTANTS open     TYPE /dmo/travel_status VALUE 'O'.
    CONSTANTS accepted TYPE /dmo/travel_status VALUE 'A'.
    CONSTANTS rejected TYPE /dmo/travel_status VALUE 'X'.
    CONSTANTS END OF travel_status.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR Travel
        RESULT result,
      earlynumbering_create FOR NUMBERING
        IMPORTING entities FOR CREATE Travel,
      setStatusToOpen FOR DETERMINE ON MODIFY
        IMPORTING keys FOR Travel~setStatusToOpen,
      validateCustomer FOR VALIDATE ON SAVE
        IMPORTING keys FOR Travel~validateCustomer.

    METHODS validateDates FOR VALIDATE ON SAVE
      IMPORTING keys FOR Travel~validateDates.
    METHODS deductDiscount FOR MODIFY
      IMPORTING keys FOR ACTION Travel~deductDiscount RESULT result.
ENDCLASS.

CLASS lhc_traveldata IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD earlynumbering_create.
    DATA entity              TYPE STRUCTURE FOR CREATE zi_db_flight_td.
    DATA travel_id_max       TYPE /dmo/travel_id.
    DATA travel_id_max_draft TYPE /dmo/travel_id.
    " change to abap_false if you get the ABAP Runtime error 'BEHAVIOUR_ILLEGAL_STATEMENT'
    DATA use_number_range    TYPE abap_bool VALUE abap_true.

    LOOP AT entities INTO entity WHERE TravelID IS NOT INITIAL.
      APPEND CORRESPONDING #( entity ) TO mapped-travel.
    ENDLOOP.

    DATA(entities_wo_travelid) = entities.
    " Remove the entries with an existing TravelID
    DELETE entities_wo_travelid WHERE TravelID IS NOT INITIAL.

    IF use_number_range = abap_true.
      TRY.
          cl_numberrange_runtime=>number_get(
              EXPORTING
                  nr_range_nr    = '01'
                  object         = '/DMO/TRV_M'
                  quantity       = CONV #( lines( entities_wo_travelid ) )
              IMPORTING
                number            = DATA(number_range_key)
                returncode        = DATA(number_range_return_code)
                returned_quantity = DATA(number_range_returned_quantity)
          ).
        CATCH cx_number_ranges INTO DATA(lx_number_ranges).
          LOOP AT entities_wo_travelid INTO entity.
            APPEND VALUE #(
                %cid      = entity-%cid
                %key      = entity-%key
                %is_draft = entity-%is_draft
                %msg      = lx_number_ranges
            ) TO reported-travel.
            APPEND VALUE #(
                %cid      = entity-%cid
                %key      = entity-%key
                %is_draft = entity-%is_draft
            ) TO failed-travel.
          ENDLOOP.
          EXIT.
      ENDTRY.

      " determine the first free travel ID from the number range
      travel_id_max = number_range_key - number_range_returned_quantity.

    ELSE.
      " determine the first free travel ID without number range
      " Get max travel ID from active table
      SELECT SINGLE FROM zdb_flight_td FIELDS MAX( travel_id ) AS travelID INTO @travel_id_max.
      " Get max travel ID from draft table
      SELECT SINGLE FROM zdb_flight_td_d FIELDS MAX( travelid ) AS travelID INTO @travel_id_max_draft.
      IF travel_id_max_draft > travel_id_max.
        travel_id_max = travel_id_max_draft.
      ENDIF.
    ENDIF.

    " Set the Travel ID for the new instances w/o ID
    LOOP AT entities_wo_travelid INTO entity.
      travel_id_max += 1.
      entity-TravelID = travel_id_max.

      APPEND VALUE #(
          %cid      = entity-%cid
          %key      = entity-%key
          %is_draft = entity-%is_draft
      ) TO mapped-travel.
    ENDLOOP.

  ENDMETHOD.

  METHOD setStatusToOpen.
    " Read travel instances of transfered keys
    READ ENTITIES OF zi_db_flight_td IN LOCAL MODE
        ENTITY Travel
        FIELDS ( OverallStatus )
        WITH CORRESPONDING #( keys )
        RESULT DATA(travels)
        FAILED DATA(travels_failed).

    " if overall travels status is already set, do nothing. i.e. remove such instance
    DELETE travels WHERE OverallStatus IS NOT INITIAL.
    CHECK travels IS NOT INITIAL.

    " else set overall travel status to open ('O')
    MODIFY ENTITIES OF zi_db_flight_td IN LOCAL MODE
        ENTITY Travel
        UPDATE SET FIELDS
        WITH VALUE #( FOR travel IN travels ( %tky = travel-%tky
                                              OverallStatus = travel_status-open ) )
        REPORTED DATA(travels_report).

    " set the changing parameter
    reported = CORRESPONDING #( DEEP travels_report ).

  ENDMETHOD.

  METHOD validateCustomer.
    DATA customers TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.

    " Read travel instances of transfered keys
    READ ENTITIES OF zi_db_flight_td IN LOCAL MODE
        ENTITY Travel
        FIELDS ( CustomerID )
        WITH CORRESPONDING #( keys )
        RESULT DATA(travels).

    " optimization of DB select: extract distinct non-initial customer IDs
    customers = CORRESPONDING #( travels
        DISCARDING DUPLICATES
        MAPPING customer_id = CustomerID EXCEPT *
    ).

    IF customers IS NOT INITIAL.
      " check if customer ID exists
      SELECT FROM /dmo/customer FIELDS customer_id
          FOR ALL ENTRIES IN @customers
          WHERE customer_id = @customers-customer_id
          INTO TABLE @DATA(valid_customers).
    ENDIF.

    " raise msg for non existing and initial customer id
    LOOP AT travels INTO DATA(travel).
      APPEND VALUE #(
          %tky        = travel-%tky
          %state_area = 'VALIDATE_CUSTOMER'
      ) TO reported-travel.

      IF travel-CustomerID IS INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky        = travel-%tky
                        %state_area = 'VALIDATE_CUSTOMER'
                        %msg        = NEW /dmo/cm_flight_messages(
                                                                textid   = /dmo/cm_flight_messages=>enter_customer_id
                                                                severity = if_abap_behv_message=>severity-error )
                        %element-CustomerID = if_abap_behv=>mk-on
        ) TO reported-travel.

      ELSEIF travel-CustomerID IS NOT INITIAL AND NOT line_exists( valid_customers[ customer_id = travel-CustomerID ] ).
        APPEND VALUE #(  %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #(  %tky                = travel-%tky
                         %state_area         = 'VALIDATE_CUSTOMER'
                         %msg                = NEW /dmo/cm_flight_messages(
                                                                customer_id = travel-customerid
                                                                textid      = /dmo/cm_flight_messages=>customer_unkown
                                                                severity    = if_abap_behv_message=>severity-error )
                         %element-CustomerID = if_abap_behv=>mk-on
        ) TO reported-travel.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validateDates.
    " Read travel instances of transfered keys
    READ ENTITIES OF zi_db_flight_td IN LOCAL MODE
        ENTITY Travel
        FIELDS ( BeginDate EndDate TravelID )
        WITH CORRESPONDING #( keys )
        RESULT DATA(travels).

    LOOP AT travels INTO DATA(travel).
      APPEND VALUE #(  %tky        = travel-%tky
                       %state_area = 'VALIDATE_DATES'
      ) TO reported-travel.

      IF travel-BeginDate IS INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = NEW /dmo/cm_flight_messages(
                                                                textid   = /dmo/cm_flight_messages=>enter_begin_date
                                                                severity = if_abap_behv_message=>severity-error )
                      %element-BeginDate = if_abap_behv=>mk-on
        ) TO reported-travel.

      ENDIF.

      IF travel-BeginDate < cl_abap_context_info=>get_system_date( ) AND travel-BeginDate IS NOT INITIAL.
*        APPEND VALUE #( %tky               = travel-%tky ) TO failed-traveldata.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = NEW /dmo/cm_flight_messages(
                                                                begin_date = travel-BeginDate
                                                                textid     = /dmo/cm_flight_messages=>begin_date_on_or_bef_sysdate
                                                                severity   = if_abap_behv_message=>severity-warning )
                        %element-BeginDate = if_abap_behv=>mk-on
        ) TO reported-travel.
      ENDIF.

      IF travel-EndDate IS INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = NEW /dmo/cm_flight_messages(
                                                               textid   = /dmo/cm_flight_messages=>enter_end_date
                                                               severity = if_abap_behv_message=>severity-error )
                        %element-EndDate   = if_abap_behv=>mk-on
        ) TO reported-travel.
      ENDIF.

      IF travel-EndDate < travel-BeginDate AND travel-BeginDate IS NOT INITIAL
                                           AND travel-EndDate IS NOT INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = NEW /dmo/cm_flight_messages(
                                                                textid     = /dmo/cm_flight_messages=>begin_date_bef_end_date
                                                                begin_date = travel-BeginDate
                                                                end_date   = travel-EndDate
                                                                severity   = if_abap_behv_message=>severity-error )
                        %element-BeginDate = if_abap_behv=>mk-on
                        %element-EndDate   = if_abap_behv=>mk-on
        ) TO reported-travel.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD deductDiscount.
    DATA travels_for_update TYPE TABLE FOR UPDATE zi_db_flight_td.
    DATA(keys_with_valid_discount) = keys.

    READ ENTITIES OF zi_db_flight_td IN LOCAL MODE
        ENTITY Travel
        FIELDS ( BookingFee )
        WITH CORRESPONDING #( keys_with_valid_discount )
        RESULT DATA(travels).

    LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).
      DATA(reduced_fee) = <travel>-BookingFee * ( 1 - 3 / 10 ).
      APPEND VALUE #(
        %tky       = <travel>-%tky
        BookingFee = reduced_fee
      ) TO travels_for_update.
    ENDLOOP.

    " update data with reduced fee
    MODIFY ENTITIES OF zi_db_flight_td IN LOCAL MODE
        ENTITY Travel
        UPDATE FIELDS ( BookingFee )
        WITH travels_for_update.

    " read changed data for action result
    READ ENTITIES OF zi_db_flight_td IN LOCAL MODE
        ENTITY Travel
        ALL FIELDS WITH
        CORRESPONDING #( travels )
        RESULT DATA(travels_with_discount).

    " set action result
    result = VALUE #( FOR travel IN travels_with_discount (
      %tky   = travel-%tky
      %param = travel
    ) ).

  ENDMETHOD.

ENDCLASS.
