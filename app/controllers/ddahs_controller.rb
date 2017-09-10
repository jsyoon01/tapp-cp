class DdahsController < ApplicationController
  protect_from_forgery with: :null_session
  include DdahUpdater
  include Authorizer
  before_action :cp_access

  def index
    if params[:utorid]
      render json: get_all_ddahs(get_all_ddah_for_utorid(params[:utorid]))
    else
      render json: get_all_ddahs(Ddah.all)
    end
  end

  def show
    if params[:utorid]
      ddahs = id_array(get_all_ddah_for_utorid(params[:utorid]))
      if ddahs.include?(params[:id])
        ddah = Ddah.find(params[:id])
        render json: ddah.format
      else
        render status: 404, json: {status: 404}
      end
    else
      ddah = Ddah.find(params[:id])
      render json: ddah.format
    end
  end

  def create
    offer = Offer.find(params[:offer_id])
    instructor = Instructor.find_by!(utorid: params[:utorid])
    ddah = Ddah.find_by(offer_id: offer[:id])
    if !ddah
      if params[:use_template]
        if template_match_offer(params[:template_id], offer)
          Ddah.create!(
            offer_id: offer[:id],
            template_id: params[:template_id],
            instructor_id: instructor[:id],
          )
        else
          render status: 404, json: {message: "Error: Mismatched Position. Operation Aborted."}
        end
      else
        Ddah.create!(
          offer_id: offer[:id],
          instructor_id: instructor[:id],
          optional: true,
        )
      end
      offer.update_attributes!(ddah_status: "Created")
      render status: 200, json: {message: "A DDAH was successfully created."}
    else
      render status: 404, json: {message: "Error: A DDAH already exists for this offer."}
    end
  end

  def template_match_offer(template_id, offer)
    position_id = offer[:position_id]
    template = Template.find(template_id)
    return position_id == template[:position_id]
  end

  def destroy
    ddah = Ddah.find(params[:id])
    ddah.allocations.each do |allocation|
      allocation.destroy!
    end
    ddah.destroy!
  end

  def update
    ddah = Ddah.find(params[:id])
    ddah.update_attributes!(ddah_params)
    update_form(ddah, param)
  end

  '''
    Template DDAH (instructor)
  '''
  def apply_template
    # TO-DO
  end

  def new_template
    # TO-DO
  end

  '''
    Send Mails (admin)
  '''
  def can_send_ddahs
    check_ddah_status(params[:ddahs], ["Approved"])
  end

  def send_ddahs
    params[:ddahs].each do |id|
      ddah = Ddah.find(id)
      offer = Offer.find(ddah[:offer_id])
      if ENV['RAILS_ENV'] != 'test'
        link = "#{ENV["domain"]}#{offer[:link]}".replace("pb", "pb/ddah")
        CpMailer.ddah_email(ddah.format,link).deliver_now!
      end
      offer.update_attributes!({ddah_status: "Pending", send_date: DateTime.now.to_s})
    end
    render status: 200, json: {message: "You've successfully sent out all the DDAH's."}
  end


  def can_nag_student
    check_ddah_status(params[:ddahs], ["Pending"])
  end

  def send_nag_student
    params[:ddahs].each do |id|
      ddah = Ddah.find(id)
      offer = Offer.find(ddah[:offer_id])
      ddah.increment!(:nag_count, 1)
      if ENV['RAILS_ENV'] != 'test'
        link = "#{ENV["domain"]}#{offer[:link]}".replace("pb", "pb/ddah")
        CpMailer.ddah_nag_email(ddah.format, link).deliver_now!
      end
    end
    render json: {message: "You've sent the nag emails."}
  end

  '''
    Set DDAH status to "Ready" (instructor)
  '''
  def can_finish_ddah
    check_ddah_status(params[:ddahs], ["None", "Created"])
  end

  def finish_ddah
    params[:ddahs].each do |id|
      ddah = Ddah.find(id)
      offer = Offer.find(ddah[:offer_id])
      offer.update_attributes!(ddah_status: "Ready", supervisor_signature: params[:signature])
    end
    render status: 200, json: {message: "The selected DDAH's have been signed and set to status 'Ready'."}
  end

  '''
    Set DDAH status to "Approved" (admin)
  '''
  def can_approve_ddah
    check_ddah_status(params[:ddahs], ["Ready"])
  end

  def approve_ddah
    params[:ddahs].each do |id|
      ddah = Ddah.find(id)
      offer = Offer.find(ddah[:offer_id])
      offer.update_attributes!(ddah_status: "Approved", ta_coord_signature: params: signature)
    end
    render status: 200, json: {message: "The selected DDAH's have been signed and set to status 'Approved'."}
  end

  '''
    Student-Facing
  '''
  def get_ddah_pdf
    # TO-DO
  end

  def accept_ddah
    offer = Offer.find(params[:offer_id])
    if offer[:ddah_status] == "Accepted"
      render status: 404, json: {message: "Error: You have already accepted this DDAH.", status: offer[:ddah_status]}
    elsif offer[:ddah_status] == "Pending"
      offer.update_attributes!(ddah_status: "Accepted", student_signature: params[:signature])
      render status: 200, json: {message: "You have accepted this DDAH.", status: offer[:ddah_status]}
    else
      render status: 404, json: {message: "Error: You cannot accept an unsent DDaH.", status: offer[:ddah_status]}
    end
  end

  private
  def ddah_params
    params.permit(:optional)
  end

  def get_all_ddahs(ddahs)
    ddahs.map do |ddah|
      ddah.format
    end
  end

  def get_all_ddah_for_utorid(utorid)
    ddahs = []
    Ddah.all.each do |ddah|
      offer = Offer.find(ddah[:offer_id])
      position = Position.find(offer[:position_id])
      position.instructors.each do |instructor|
        if instructor[:utorid] == utorid
          ddahs.push(ddah)
        end
      end
    end
    return ddahs
  end

  def check_ddah_status(ddahs, status)
    invalid = []
    ddahs.each do |ddah_id|
      ddah = Ddah.find(ddah_id)
      offer = Offer.find(ddah[:offer_id])
      if !(status.include? offer[:ddah_status])
        invalid.push(ddah[:id])
      end
    end
    if invalid.length > 0
      render status: 404, json: {invalid_offers: invalid}
    end
  end


end