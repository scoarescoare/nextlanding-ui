'use strict'

angular.module('search.services')
.factory 'SearchWizardModel', ($rootScope, $timeout, $state, $location, Restangular, Lodash, Analytics, AppConfig) ->
    search = {}
    amenities = {}
    paymentPending = false
    initFired = false

    steps = [
      'locationStep'
      'descriptionStep'
      'generalDetailsStep'
      'amenityDetailsStep'
      'contactStep'
      'paymentStep'
    ]

    #if the same controller consumes this model many times, we only want to initialize one time
    init = ->
      unless initFired
        #this needs to be done in the next digest becuase our subscribers won't be registered until then
        $timeout(broadcastCurrentStep)

        initFired = true
        #get the initial response
        #we're doing a get to return just 1 item - this is unconventional and requires a .customPUT call later in the model
        Restangular.one('search').all('potential_search_init').getList().then (response) ->
          if response
            #this is a hack to ensure post/puts go to same resource depending if the user comes back or not
            response.route = "search/potential_search_init"
            parseSearch(response)

        Restangular.all('amenity').getList().then (response) ->
          amenities = response

    broadcastCurrentStep = ->
      Analytics.trackEvent "Started: #{currentStep} Step"
      $rootScope.$broadcast "currentStep:changed:#{currentStep}"

    currentStep = steps[0]

    proceed = ->
      if search.id
        #use customput because restangular expects a getList to return multiple items
        #this is a hack to prevent restangular from attachin an id to the path
        debugger
        response = search.customPUT(angular.extend(search, id: null))
      else
        response = Restangular.one('search').all('potential_search_init').post(search)

      do (currentStep) ->
        #put this in a closure as they may advance steps very quickly
        response.then (response) ->
          parseSearch(response)
          trackUser(response, currentStep)

      nextStep = steps.indexOf(currentStep) + 1

      if steps.length == nextStep
        console.log('done')
      else
        currentStep = steps[nextStep]
        broadcastCurrentStep()

    retreat = ->
      currentStep = steps[steps.indexOf(currentStep) - 1]
      broadcastCurrentStep()

    #this is its own function because of mutability of the current step variable
    getCurrentStep = ->
      currentStep

    isLastStep = ->
      getCurrentStep() == steps[steps.length - 1]

    parseSearch = (response) ->
      search = response
      search.search_attrs = angular.fromJson response.search_attrs

    trackUser = (response, currentStep) ->
      if currentStep is 'contactStep'
        $rootScope.$broadcast "tracking:user:email", search.search_attrs.email_address

    toggleAmenity = (amenityId) ->
      search.search_attrs.amenities ||= []
      if amenityId in search.search_attrs.amenities
        Lodash.remove(search.search_attrs.amenities, amenityId)
      else
        search.search_attrs.amenities.push amenityId

    processPayment = (token) ->
      search.token = token
      paymentPending = true
      Restangular.one('search').all('potential_search_complete').post(search).then (->
        paymentPending = false
        $rootScope.$broadcast "tracking:user:signup", emailAddress: search.search_attrs.email_address
        $rootScope.$broadcast "tracking:user:purchase", AppConfig.SEARCH_PRICE
        $state.go 'thankYou'
        #find a way to remove the back button - simulate post redirect get
        $location.replace()
      ), ->
        paymentPending = false
        alert ('error processing your payment')


    retVal =
      steps: steps
      init: init
      getCurrentStep: getCurrentStep
      proceed: proceed
      retreat: retreat
      isLastStep: isLastStep
      parseSearch: parseSearch
      toggleAmenity: toggleAmenity
      processPayment: processPayment

    # defining a getter property here because the search is constantly replaced by the restangular responses
    # using angular.extend was causing problems with re-writing the object.
    # we could just make search a function called getSearch() but then each template would be look like:
    # <input ng-model='model.getSearch().location.name....
    Object.defineProperty retVal, 'search',
      get: ->
        search

    Object.defineProperty retVal, 'amenities',
      get: ->
        amenities

    Object.defineProperty retVal, 'paymentPending',
      get: ->
        paymentPending

    retVal
