class PatientsController < ApplicationController
  def show
    #find the user priviledges
    @super_user = false
    @nurse = false
    @clinician  = false
    @doctor     = false
    @registration_clerk  = false

    @user = User.find(session[:user_id])
    @user_privilege = @user.user_roles.collect{|x|x.role}

    if @user_privilege.first.downcase.include?("superuser")
      @super_user = true
    elsif @user_privilege.first.downcase.include?("clinician")
      @clinician  = true
    elsif @user_privilege.first.downcase.include?("nurse")
      @nurse  = true
    elsif @user_privilege.first.downcase.include?("doctor")
      @doctor     = true
    elsif @user_privilege.first.downcase.include?("registration clerk")
      @registration_clerk  = true
    end
    
    @patient      = Patient.find(params[:id] || session[:patient_id]) rescue nil
    void_encounter if (params[:void] && params[:void] == 'true')
    @encounters   = @patient.encounters.current.active.find(:all)
    excluded_encounters = ["Registration", "Diabetes history","Complications", #"Diabetes test",
      "General health", "Diabetes treatments", "Diabetes admissions","Hospital admissions",
      "Hypertension management", "Past diabetes medical history"]
    @encounter_names = @patient.encounters.active.map{|encounter| encounter.name}.uniq.delete_if{ |encounter| excluded_encounters.include? encounter.humanize } rescue []
    ignored_concept_id = Concept.find_by_name("NO").id;
    
    @observations = Observation.find(:all, :order => 'obs_datetime DESC', 
      :limit => 50, :conditions => ["person_id= ? AND obs_datetime < ? AND value_coded != ?",
        @patient.patient_id, Time.now.to_date, ignored_concept_id])

    @observations.delete_if { |obs| obs.value_text.downcase == "no" rescue nil }

    # delete encounters that are not required for display on patient's summary
    @lab_results_ids = [Concept.find_by_name("Urea").id, Concept.find_by_name("Urine Protein").id, Concept.find_by_name("Creatinine").id]
    @encounters.map{ |encounter| (encounter.name == "DIABETES TEST" && encounter.observations.delete_if{|obs| !(@lab_results_ids.include? obs.concept.id)})}
    @encounters.delete_if{|encounter|(encounter.observations == [])}

    @obs_datetimes = @observations.map { |each|each.obs_datetime.strftime("%d-%b-%Y")}.uniq

    @vitals = Encounter.find(:all, :order => 'encounter_datetime DESC',
      :limit => 50, :conditions => ["patient_id= ? AND encounter_datetime < ? ",
        @patient.patient_id, Time.now.to_date])

    @patient_treatements = @patient.treatments

    diabetes_id       = Concept.find_by_name("DIABETES MEDICATION").id

    @patient_diabetes_treatements     = []
    @patient_hypertension_treatements = []

    @patient_diabetes_treatements = @patient.aggregate_treatments

    selected_medical_history = ['DIABETES DIAGNOSIS DATE','SERIOUS CARDIAC PROBLEM','STROKE','HYPERTENSION','TUBERCULOSIS']
    @medical_history_ids = selected_medical_history.map { |medical_history| Concept.find_by_name(medical_history).id }
    @significant_medical_histor    y = []
    @observations.each { |obs| @significant_medical_history << obs if @medical_history_ids.include? obs.concept_id}

    @arv_number = @patient.arv_number rescue nil
    @status     = @patient.hiv_status
    #@status =Concept.find(Observation.find(:first,  :conditions => ["voided = 0 AND person_id= ? AND concept_id = ?",@patient.person.id, Concept.find_by_name('HIV STATUS').id], :order => 'obs_datetime DESC').value_coded).name.name rescue 'UNKNOWN'
    @hiv_test_date    = @patient.hiv_test_date rescue "UNKNOWN"
    @hiv_test_date = "Unkown" if @hiv_test_date.blank?
    @remote_art_info  = Patient.remote_art_info(@patient.national_id) rescue nil

    @recents = Patient.recent_screen_complications(@patient.patient_id)

    # set the patient's medication period
    @patient_medication_period = Patient.patient_diabetes_medication_duration(@patient.patient_id)
    
    render :template => 'patients/show', :layout => 'menu'
  end
  
  def print_registration
    @patient = Patient.find(params[:id] || params[:patient_id] || session[:patient_id]) rescue nil
    print_and_redirect("/patients/national_id_label/?patient_id=#{@patient.id}", next_task(@patient))  
  end
  
  def print_visit
    @patient = Patient.find(params[:id] || params[:patient_id] || session[:patient_id]) rescue nil
    print_and_redirect("/patients/visit_label/?patient_id=#{@patient.id}", next_task(@patient))  
  end

  def print_complications
    @patient = Patient.find(params[:id] || params[:patient_id] || session[:patient_id]) rescue nil
    next_url = "/patients/mastercard?patient_id=#{@patient.id}"
    print_and_redirect("/patients/complications_label/?patient_id=#{@patient.id}", next_url)
  end
  
  def national_id_label
    print_string = Patient.find(params[:patient_id]).national_id_label rescue (raise "Unable to find patient (#{params[:patient_id]}) or generate a national id label for that patient")
    send_data(print_string,:type=>"application/label; charset=utf-8", :stream=> false, :filename=>"#{params[:patient_id]}#{rand(10000)}.lbl", :disposition => "inline")
  end
  
  def visit_label
    print_string = Patient.find(params[:patient_id]).visit_label(session[:user_id]) rescue (raise "Unable to find patient (#{params[:patient_id]}) or generate a visit label for that patient")
    send_data(print_string,:type=>"application/label; charset=utf-8", :stream=> false, :filename=>"#{params[:patient_id]}#{rand(10000)}.lbl", :disposition => "inline")
  end

  def complications_label
    print_string = Patient.find(params[:patient_id]).complications_label(session[:user_id]) #rescue (raise "Unable to find patient (#{params[:patient_id]}) or generate a visit label for that patient")
    send_data(print_string,:type=>"application/label; charset=utf-8", :stream=> false, :filename=>"#{params[:patient_id]}#{rand(10000)}.lbl", :disposition => "inline")
  end

  def hiv_status
    #find patient object and arv number
    @patient = Patient.find(params[:patient_id] || params[:id] || session[:patient_id]) rescue nil 
    @arv_number = @patient.arv_number rescue nil
    @status     = @patient.hiv_status
    #@status =Concept.find(Observation.find(:first,  :conditions => ["voided = 0 AND person_id= ? AND concept_id = ?",@patient.person.id, Concept.find_by_name('HIV STATUS').id], :order => 'obs_datetime DESC').value_coded).name.name rescue 'UNKNOWN'
    @hiv_test_date    = @patient.hiv_test_date rescue "UNKNOWN"
    @hiv_test_date = "Unknown" if @hiv_test_date.blank?
    
    @remote_art_info  = Patient.remote_art_info(@patient.national_id) rescue nil

    render :template => 'patients/hiv_status', :layout => 'menu'
  end

  def dashboard
    #find the user priviledges
    @super_user = false
    @clinician  = false
    @doctor     = false
    @registration_clerk  = false

    @user = User.find(session[:user_id])
    @user_privilege = @user.user_roles.collect{|x|x.role}

    if @user_privilege.include?("superuser")
      @super_user = true
    elsif @user_privilege.include?("clinician")
      @clinician  = true
    elsif @user_privilege.include?("doctor")
      @doctor     = true
    elsif @user_privilege.include?("registration clerk")
      @registration_clerk  = true
    end
    
       
    @patient = Patient.find(params[:id] || session[:patient_id]) rescue nil 
    @encounters = @patient.encounters.current.active.find(:all)
    @patient      = Patient.find(params[:id] || session[:patient_id]) rescue nil
    @encounters   = @patient.encounters.current.active.find(:all)
    @observations = Observation.find(:all, :order => 'obs_datetime DESC',
      :limit => 50, :conditions => ["person_id= ? AND obs_datetime < ? ",
        @patient.patient_id, Time.now.to_date])
    render :template => 'patients/dashboard', :layout => 'menu'
  end

  def discharge
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil 
    render :template => 'patients/discharge', :layout => 'menu'
  end

  def demographics
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
    @person = @patient.person
    @address = @person.addresses.last
    render :layout => 'menu'
  end

  def mastercard
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil
    void_encounter if (params[:void] && params[:void] == 'true')
    @person = @patient.person
    @encounters = @patient.encounters.find_all_by_encounter_type(EncounterType.find_by_name('DIABETES TEST').id)
    @observations = @encounters.map(&:observations).flatten
    @obs_datetimes = @observations.map { |each|each.obs_datetime.strftime("%d-%b-%Y")}.uniq
    @address = @person.addresses.last

    diabetes_test_id = EncounterType.find_by_name('Diabetes Test').id

    #TODO: move this code to Patient model
    # Creatinine
    creatinine_id = Concept.find_by_name('CREATININE').id
    @creatinine_obs = @patient.person.observations.find(:all,
      :joins => :encounter,
      :conditions => ['encounter_type = ? AND concept_id = ?',
        diabetes_test_id, creatinine_id],
      :order => 'obs_datetime DESC')

    # Urine Protein
    urine_protein_id = Concept.find_by_name('URINE PROTEIN').id
    @urine_protein_obs = @patient.person.observations.find(:all,
      :joins => :encounter,
      :conditions => ['encounter_type = ? AND concept_id = ?',
        diabetes_test_id, urine_protein_id],
      :order => 'obs_datetime DESC')

    # Foot Check
    @foot_check_encounters = @patient.encounters.find(:all,
      :joins => :observations,
      :conditions => ['concept_id IN (?)',
        ConceptName.find_all_by_name(['RIGHT FOOT/LEG',
            'LEFT FOOT/LEG', 'LEFT HAND/ARM', 'RIGHT HAND/ARM']).map(&:concept_id)],
      :order => 'obs_datetime DESC').uniq

    if @foot_check_encounters.nil?
      @foot_check_encounters = []
    end

    @foot_check_obs = {}
    
    @foot_check_encounters.each{|e|
      value = @patient.person.observations.find(:all,
        :joins => :encounter,
        :conditions => ['encounter_type = ? AND encounter.encounter_id IN (?)',
          diabetes_test_id, e.encounter_id],
        :order => 'obs_datetime DESC')

      unless value.nil?
        @foot_check_obs[e.encounter_id] = value
      end
    }
    #raise @foot_check_obs.to_yaml

    # Visual Acuity RIGHT EYE FUNDOSCOPY
    @visual_acuity_encounters = @patient.encounters.find(:all,
      :joins => :observations,
      :conditions => ['concept_id IN (?)',
        ConceptName.find_all_by_name(['LEFT EYE VISUAL ACUITY',
            'RIGHT EYE VISUAL ACUITY']).map(&:concept_id)],
      :order => 'obs_datetime DESC').uniq

    if @visual_acuity_encounters.nil?
      @visual_acuity_encounters = []
    end
    
    @visual_acuity_obs = {}
    
    @visual_acuity_encounters.each{|e|
      @visual_acuity_obs[e.encounter_id] = @patient.person.observations.find(:all,
        :joins => :encounter,
        :conditions => ['encounter_type = ? AND encounter.encounter_id = ?',
          diabetes_test_id, e.encounter_id],
        :order => 'obs_datetime DESC')
    }
    #raise @visual_acuity_encounters.to_yaml

    # Fundoscopy
    @fundoscopy_encounters = @patient.encounters.find(:all,
      :joins => :observations,
      :conditions => ['concept_id IN (?)',
        ConceptName.find_all_by_name(['LEFT EYE FUNDOSCOPY',
            'RIGHT EYE FUNDOSCOPY']).map(&:concept_id)],
      :order => 'obs_datetime DESC').uniq

    if @fundoscopy_encounters.nil?
      @fundoscopy_encounters = []
    end

    @fundoscopy_obs = {}
    
    @fundoscopy_encounters.each{|e|
      @fundoscopy_obs[e.encounter_id] = @patient.person.observations.find(:all,
        :joins => :encounter,
        :conditions => ['encounter_type = ? AND encounter.encounter_id IN (?)',
          diabetes_test_id, e.encounter_id],
        :order => 'obs_datetime DESC')
    }
    #raise @foot_check_obs.to_yaml
    
    # Urea
    urea_id = Concept.find_by_name('UREA').id
    @urea_obs = @patient.person.observations.find(:all,
      :joins => :encounter,
      :conditions => ['encounter_type = ? AND concept_id = ?',
        diabetes_test_id, urea_id],
      :order => 'obs_datetime DESC')
    render :layout => 'menu'
  end

  def generate_booking
    @patient = Patient.find(params[:patient_id]  || params[:id] || session[:patient_id]) rescue nil

    @type = EncounterType.find_by_name("APPOINTMENT").id rescue nil
    if(@type)
      @enc = Encounter.find(:all, :conditions =>
          ["voided = 0 AND encounter_type = ?", @type])

      @counts = {}

      @enc.each{|e|
        yr = e.encounter_datetime.to_date.strftime("%Y")
        mt = e.encounter_datetime.to_date.strftime("%m").to_i-1
        dy = e.encounter_datetime.to_date.strftime("%d").to_i

        if(!@counts[(yr.to_s + "-" + mt.to_s + "-" + dy.to_s)])
          @counts[(yr.to_s + "-" + mt.to_s + "-" + dy.to_s)] = {}
          @counts[(yr.to_s + "-" + mt.to_s + "-" + dy.to_s)]["count"] = 0
        end

        @counts[(yr.to_s + "-" + mt.to_s + "-" + dy.to_s)][e.patient_id] = true
        @counts[(yr.to_s + "-" + mt.to_s + "-" + dy.to_s)]["count"] += 1

      }

    end
    
    render :layout => 'menu'
  end

  def make_booking
    if(params[:patient_id])
      @type = EncounterType.find_by_name("APPOINTMENT").id rescue nil

      if(@type)
        @enc = Encounter.find(:last, :conditions =>
            ["voided = 0 AND patient_id = ? AND encounter_type = ? AND DATE_FORMAT(encounter_datetime, '%Y-%m-%d') = ?",
            params[:patient_id], @type, params[:appointment_date]])

        unless @enc
          @enc = Encounter.new(:encounter_type => @type,
            :patient_id => params[:patient_id],
            :provider_id => session[:user_id],
            :encounter_datetime => params[:appointment_date],
            :creator => session[:user_id],
            :voided => 0
          )

          @enc.save
        end
        
      end
    end
  end

  def remove_booking
    if(params[:patient_id])
      @type = EncounterType.find_by_name("APPOINTMENT").id rescue nil
      if(@type)
        @enc = Encounter.find(:last, :conditions =>
            ["voided = 0 AND patient_id = ? AND encounter_type = ? AND DATE_FORMAT(encounter_datetime, '%Y-%m-%d') = ?",
            params[:patient_id], @type, params[:appointment_date]])

        if(@enc)
          reason = ""

          if(params[:appointment_date])
            if(params[:appointment_date].to_date < Time.now.to_date)
              reason = "Defaulted"
            elsif(params[:appointment_date].to_date == Time.now.to_date)
              reason = "Attended"
            elsif(params[:appointment_date].to_date > Time.now.to_date)
              reason = "Pre-cancellation"
            else
              reason = "General reason"
            end
          end

          @enc.update_attributes(:voided => 1, :date_voided => params[:appointment_date],
            :voided_by => session[:user_id], :void_reason => reason)

        end
      end
    end
  end

  def search_appointments
    if(params[:patient_id])
      @type = EncounterType.find_by_name("APPOINTMENT").id rescue nil
      if(@type)
        @enc = Encounter.find(:all, :conditions =>
            ["voided = 0 AND patient_id = ? AND encounter_type = ?",
            params[:patient_id], @type])

        @counts = {}

        @enc.each{|e|
          yr = e.encounter_datetime.to_date.strftime("%Y")
          mt = e.encounter_datetime.to_date.strftime("%m").to_i-1
          dy = e.encounter_datetime.to_date.strftime("%d").to_i

          if(!@counts[(yr.to_s + "-" + mt.to_s + "-" + dy.to_s)])
            @counts[(yr.to_s + "-" + mt.to_s + "-" + dy.to_s)] = {}
          end

          @counts[(yr.to_s + "-" + mt.to_s + "-" + dy.to_s)][e.patient_id] = true
          
        }

        render :text => ""
      end
    end
  end

end
