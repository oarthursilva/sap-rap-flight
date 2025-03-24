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
        REQUEST requested_authorizations FOR TravelData
        RESULT result,
      earlynumbering_create FOR NUMBERING
        IMPORTING entities FOR CREATE TravelData,
      setStatusToOpen FOR DETERMINE ON MODIFY
        IMPORTING keys FOR TravelData~setStatusToOpen.
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
      APPEND CORRESPONDING #( entity ) TO mapped-traveldata.
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
            ) TO reported-traveldata.
            APPEND VALUE #(
                %cid      = entity-%cid
                %key      = entity-%key
                %is_draft = entity-%is_draft
            ) TO failed-traveldata.
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
      ) TO mapped-traveldata.
    ENDLOOP.

  ENDMETHOD.

  METHOD setStatusToOpen.
    " Read travel instances of transfered keys
    READ ENTITIES OF zi_db_flight_td IN LOCAL MODE
        ENTITY TravelData
        FIELDS ( OverallStatus )
        WITH CORRESPONDING #( keys )
        RESULT DATA(travels)
        FAILED DATA(travels_failed).

    " if overall travels status is already set, do nothing. i.e. remove such instance
    DELETE travels WHERE OverallStatus IS NOT INITIAL.
    CHECK travels IS NOT INITIAL.

    " else set overall travel status to open ('O')
    MODIFY ENTITIES OF zi_db_flight_td IN LOCAL MODE
        ENTITY TravelData
        UPDATE SET FIELDS
        WITH VALUE #( FOR travel IN travels ( %tky = travel-%tky
                                              OverallStatus = travel_status-open ) )
        REPORTED DATA(travels_report).

    " set the changing parameter
    reported = CORRESPONDING #( DEEP travels_report ).

  ENDMETHOD.

ENDCLASS.
